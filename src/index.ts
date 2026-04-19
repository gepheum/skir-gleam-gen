// TODO: keyed arrays
// TODO: recrusive fields...
// TODO: in the generated code, ask AI if some things are not optimal
// TODO: signify that Serializer.adapter is for internal use...
// TODO: fix all comments
// TODO: the logic for determining what types to import is flawed...
// TODO: use enum for UnrecognizedValues...

import {
  type CodeGenerator,
  type Constant,
  type Doc,
  type RecordKey,
  type RecordLocation,
  type ResolvedType,
  convertCase,
} from "skir-internal";
import { z } from "zod";
import { getModuleDir, getTypeName, toFieldName } from "./naming.js";
import { TypeSpeller } from "./type_speller.js";

const Config = z.strictObject({});

type Config = z.infer<typeof Config>;

/**
 * Information about the Gleam source file generated for one Skir module.
 */
interface GroupInfo {
  /** Records in this group (sorted in original declaration order). */
  records: readonly RecordLocation[];
  /** Constants declared at the top-level of the corresponding Skir module. */
  constants: readonly Constant<false>[];
  /** Output file path relative to outDir, e.g. "gepheum/foo/bar__baz.gleam". */
  outputPath: string;
  /** Gleam import path, e.g. "skirout/gepheum/foo/bar__baz". */
  importPath: string;
  /** Gleam import alias, e.g. "gepheum__foo__bar__baz". */
  alias: string;
  /** Set of all record keys contained in this group (for fast lookup). */
  keySet: ReadonlySet<RecordKey>;
}

class GleamCodeGenerator implements CodeGenerator<Config> {
  readonly id = "skir-gleam-gen";
  readonly configType = Config;

  generateCode(input: CodeGenerator.Input<Config>): CodeGenerator.Output {
    const { recordMap } = input;
    const outputFiles: CodeGenerator.OutputFile[] = [];

    // First pass: compute groups and name maps for every module.
    const keyToGroup = new Map<RecordKey, GroupInfo>();
    const pathToGroup = new Map<string, GroupInfo>(); // .skir module path → GroupInfo
    const allGroups: GroupInfo[] = [];
    const uniqueTypeNames = new Map<RecordKey, string>();
    const allCtorNames = new Map<string, string>();
    for (const module of input.modules) {
      const groups = computeGroupsForModule(
        module.records,
        module.constants as readonly Constant<false>[],
        module.path,
      );
      for (const group of groups) {
        allGroups.push(group);
        pathToGroup.set(module.path, group);
        for (const key of group.keySet) {
          keyToGroup.set(key, group);
        }
      }
      const { typeNames, ctorNames } = computeModuleNames(module.records);
      for (const [k, v] of typeNames) uniqueTypeNames.set(k, v);
      for (const [k, v] of ctorNames) allCtorNames.set(k, v);
    }

    // Second pass: generate code for each group.
    for (const module of input.modules) {
      const group = pathToGroup.get(module.path);
      if (!group) continue;
      outputFiles.push({
        path: group.outputPath,
        code: new GleamSourceFileGenerator(
          group,
          recordMap,
          keyToGroup,
          uniqueTypeNames,
          allCtorNames,
          Object.keys(module.pathToImportedNames),
          pathToGroup,
        ).generate(),
      });
    }

    return { files: outputFiles };
  }
}

/**
 * Returns a single GroupInfo containing all records from the given Skir module.
 * All types from one .skir file are co-located in one Gleam module.
 */
function computeGroupsForModule(
  records: readonly RecordLocation[],
  constants: readonly Constant<false>[] = [],
  modulePath?: string,
): GroupInfo[] {
  if (records.length === 0 && constants.length === 0) return [];
  let moduleDir: string;
  if (records.length > 0) {
    moduleDir = getModuleDir(records[0]!.modulePath);
  } else if (modulePath) {
    moduleDir = getModuleDir(modulePath);
  } else {
    return [];
  }
  return [
    {
      records: [...records],
      constants: [...constants],
      outputPath: `${moduleDir}.gleam`,
      importPath: `skirout/${moduleDir}`,
      alias: moduleDir.replace(/\//g, "__") + "_",
      keySet: new Set(records.map((r) => r.record.key)),
    },
  ];
}

/**
 * Computes the set of record keys whose default value can be represented as a
 * Gleam `const` (as opposed to a zero-arg `fn`). A record can use `const` iff:
 *   - It is an enum (always defaults to `Unknown(option.None)`)
 *   - It is a struct and none of its non-hard-recursive fields transitively
 *     contain a `timestamp` primitive (which requires a function call to
 *     construct its default value).
 *
 * Computed via an optimistic fixed-point: assume all records can use `const`,
 * then propagate "cannot" for timestamp fields and for fields whose type
 * cannot use `const`.
 */
function computeConstDefaultKeys(
  recordMap: ReadonlyMap<RecordKey, RecordLocation>,
): Set<RecordKey> {
  const canUseConst = new Map<RecordKey, boolean>();
  for (const key of recordMap.keys()) {
    canUseConst.set(key, true);
  }

  const typeBlocksConst = (type: ResolvedType): boolean => {
    switch (type.kind) {
      case "primitive":
        return type.primitive === "timestamp";
      case "array":
        return typeBlocksConst(type.item);
      case "optional":
        return typeBlocksConst(type.other);
      case "record":
        return canUseConst.get(type.key) === false;
    }
  };

  let changed = true;
  while (changed) {
    changed = false;
    for (const [key, rec] of recordMap) {
      if (rec.record.recordType !== "struct") continue;
      if (canUseConst.get(key) === false) continue;
      for (const field of rec.record.fields) {
        if (field.isRecursive === "hard") continue;
        if (field.type && typeBlocksConst(field.type)) {
          canUseConst.set(key, false);
          changed = true;
          break;
        }
      }
    }
  }

  return new Set(
    [...canUseConst.entries()].filter(([, v]) => v).map(([k]) => k),
  );
}

/**
 * Computes unique Gleam names for all types and variant constructors in a
 * single Skir module using BFS depth-order processing with "X" collision
 * avoidance. Both type names and constructor names share the same collision
 * namespace to avoid any ambiguity.
 *
 * Returns:
 * - typeNames: RecordKey → Gleam type name (UpperCamel)
 * - ctorNames: "${recordKey}:${variantText}" → Gleam constructor name
 *   (use "__unknown__" as the variant text for the implicit Unknown constructor)
 */
function computeModuleNames(records: readonly RecordLocation[]): {
  typeNames: Map<RecordKey, string>;
  ctorNames: Map<string, string>;
} {
  const taken = new Set<string>();
  const typeNames = new Map<RecordKey, string>();
  const ctorNames = new Map<string, string>();

  if (records.length === 0) return { typeNames, ctorNames };

  // Build a lookup from ancestor-path string → record key.
  const pathToKey = new Map<string, RecordKey>();
  for (const rec of records) {
    const path = rec.recordAncestors.map((a) => a.name.text).join("\0");
    pathToKey.set(path, rec.record.key);
  }

  const parentKeyOf = (rec: RecordLocation): RecordKey | undefined => {
    if (rec.recordAncestors.length <= 1) return undefined;
    const parentPath = rec.recordAncestors
      .slice(0, -1)
      .map((a) => a.name.text)
      .join("\0");
    return pathToKey.get(parentPath);
  };

  // Group records by depth (0 = top-level).
  const byDepth: RecordLocation[][] = [];
  for (const rec of records) {
    const depth = rec.recordAncestors.length - 1;
    while (byDepth.length <= depth) byDepth.push([]);
    byDepth[depth]!.push(rec);
  }

  // Assign a unique name, appending "X" until there is no collision.
  const assign = (candidate: string): string => {
    while (taken.has(candidate)) candidate += "X";
    taken.add(candidate);
    return candidate;
  };

  // Process each depth level. At depth N we assign:
  //   - type names for depth-N records
  //   - constructor names for variants of depth-(N-1) enums
  // We run one extra iteration (depth == byDepth.length) to process
  // variant constructors of the deepest enums.
  for (let depth = 0; depth <= byDepth.length; depth++) {
    // Assign type names for records at this depth.
    for (const rec of byDepth[depth] ?? []) {
      const ownName = convertCase(
        rec.recordAncestors.at(-1)!.name.text,
        "UpperCamel",
      );
      const pk = parentKeyOf(rec);
      const parentName = pk !== undefined ? (typeNames.get(pk) ?? "") : "";
      typeNames.set(rec.record.key, assign(parentName + ownName));
    }

    // Assign constructor names for variants of depth-(depth-1) enums.
    if (depth > 0) {
      for (const rec of byDepth[depth - 1] ?? []) {
        if (rec.record.recordType !== "enum") continue;
        const typeName = typeNames.get(rec.record.key)!;
        // Implicit Unknown constructor.
        ctorNames.set(
          `${rec.record.key}:__unknown__`,
          assign(typeName + "Unknown"),
        );
        // User-defined variant constructors.
        for (const variant of rec.record.fields) {
          const variantPart = convertCase(variant.name.text, "UpperCamel");
          ctorNames.set(
            `${rec.record.key}:${variant.name.text}`,
            assign(typeName + variantPart),
          );
        }
      }
    }
  }

  return { typeNames, ctorNames };
}

// Generates the code for one Gleam source file (one GroupInfo → one file).
/** Ordered list of client library module paths and their import aliases. */
const CLIENT_MODULES: ReadonlyArray<readonly [string, string]> = [
  ["gleam/option", "option_"],
  ["gleam/time/timestamp", "timestamp_"],
  ["skir_client", "skir_client_"],
  ["skir_client/internal/struct_serializer", "struct_serializer_"],
  ["gleam/list", "list_"],
  ["gleam/result", "result_"],
  ["skir_client/internal/enum_serializer", "enum_serializer_"],
  ["skir_client/internal/unrecognized", "unrecognized_"],
] as const;

class GleamSourceFileGenerator {
  private code = "";
  private readonly neededModules = new Set<string>();
  private readonly typeSpeller: TypeSpeller;
  private readonly constDefaultKeys: ReadonlySet<RecordKey>;

  constructor(
    private readonly group: GroupInfo,
    recordMap: ReadonlyMap<RecordKey, RecordLocation>,
    private readonly keyToGroup: ReadonlyMap<RecordKey, GroupInfo>,
    private readonly uniqueTypeNames: ReadonlyMap<RecordKey, string>,
    private readonly ctorNames: ReadonlyMap<string, string>,
    private readonly importedModulePaths: readonly string[],
    private readonly pathToGroup: ReadonlyMap<string, GroupInfo>,
  ) {
    // Returns the unique Gleam type name for a given record key.
    const uniqueNameFor = (key: RecordKey): string => {
      return uniqueTypeNames.get(key) ?? getTypeName(recordMap.get(key)!);
    };

    // Compute the function name for a given record key and base name.
    // The prefix is the full ancestor path in lower_underscore joined by "__".
    const fnNameFor = (key: RecordKey, base: string): string => {
      const rec = recordMap.get(key)!;
      const prefix = rec.recordAncestors
        .map((a) => convertCase(a.name.text, "lower_underscore"))
        .join("__");
      return `${prefix}_${base}`;
    };

    const typeExprFor = (key: RecordKey): string => {
      const typeName = uniqueNameFor(key);
      if (group.keySet.has(key)) return typeName;
      return `${keyToGroup.get(key)!.alias}.${typeName}`;
    };

    const constDefaultKeys = computeConstDefaultKeys(recordMap);
    this.constDefaultKeys = constDefaultKeys;

    const defaultExprFor = (key: RecordKey): string => {
      const rec = recordMap.get(key)!;
      const baseName = rec.record.recordType === "enum" ? "unknown" : "default";
      const name = fnNameFor(key, baseName);
      const isConst = constDefaultKeys.has(key);
      if (group.keySet.has(key)) return isConst ? name : `${name}()`;
      const alias = keyToGroup.get(key)!.alias;
      return isConst ? `${alias}.${name}` : `${alias}.${name}()`;
    };

    const serializerExprFor = (key: RecordKey): string => {
      const fn = fnNameFor(key, "serializer");
      if (group.keySet.has(key)) return `${fn}()`;
      return `${keyToGroup.get(key)!.alias}.${fn}()`;
    };

    this.typeSpeller = new TypeSpeller(
      recordMap,
      typeExprFor,
      defaultExprFor,
      serializerExprFor,
      this.neededModules,
    );
  }

  generate(): string {
    // http://patorjk.com/software/taag/#f=Doom&t=Do%20not%20edit
    this.push(
      `//  ______                        _               _  _  _
//  |  _  \\                      | |             | |(_)| |
//  | | | |  ___    _ __    ___  | |_    ___   __| | _ | |_
//  | | | | / _ \\  | '_ \\  / _ \\ | __|  / _ \\ / _\` || || __|
//  | |/ / | (_) | | | | || (_) || |_  |  __/| (_| || || |_
//  |___/   \\___/  |_| |_| \\___/  \\__|  \\___| \\__,_||_| \\__|
//
// Generated by skir-gleam-gen
// Home: https://github.com/gepheum/skir-gleam-gen
//
// Do not edit this file manually.

`,
    );

    // Save the header (banner comment), then generate all body code into
    // this.code. Body generation populates this.neededModules.
    const header = this.code;
    this.code = "";

    for (const recordLocation of this.group.records) {
      const { record } = recordLocation;
      if (record.recordType === "struct") {
        this.writeTypesForStruct(recordLocation);
      } else {
        this.writeTypesForEnum(recordLocation);
      }
    }

    this.writeConstants();

    const body = this.code;

    // Build imports from the collected set, in canonical order.
    this.code = header;
    this.writeImports();
    this.push(body);

    return this.joinLinesAndFixFormatting();
  }

  private writeImports(): void {
    // Client library modules, in canonical order.
    for (const [modulePath, alias] of CLIENT_MODULES) {
      if (this.neededModules.has(modulePath)) {
        this.push(`import ${modulePath} as ${alias}\n`);
      }
    }

    // Cross-module skirout imports.
    const seenGroupAliases = new Set<string>();
    for (const importedPath of this.importedModulePaths) {
      const refGroup = this.pathToGroup.get(importedPath);
      if (!refGroup || refGroup === this.group) continue;
      if (seenGroupAliases.has(refGroup.alias)) continue;
      seenGroupAliases.add(refGroup.alias);
      this.push(`import ${refGroup.importPath} as ${refGroup.alias}\n`);
    }

    this.push("\n");
  }

  private writeConstants(): void {
    for (const constant of this.group.constants) {
      if (!constant.type || constant.valueAsDenseJson === undefined) continue;
      this.neededModules.add("skir_client");
      const fnName = convertCase(constant.name.text, "lower_underscore");
      const gleamType = this.typeSpeller.getGleamType(constant.type);
      const serializerExpr = this.typeSpeller.getSerializerExpression(
        constant.type,
      );
      const jsonStr = JSON.stringify(JSON.stringify(constant.valueAsDenseJson));
      const doc = commentify(docToCommentText(constant.doc));
      if (doc) this.push(doc);
      this.push(
        `pub fn ${fnName}() -> ${gleamType} {
` +
          `let assert Ok(v) = skir_client_.from_json(
` +
          `${serializerExpr},
` +
          `${jsonStr},
` +
          `)
` +
          `v
` +
          `}

`,
      );
    }
  }

  private writeTypesForStruct(struct: RecordLocation): void {
    this.neededModules.add("gleam/option");
    this.neededModules.add("skir_client");
    this.neededModules.add("skir_client/internal/struct_serializer");
    this.neededModules.add("gleam/list");
    this.neededModules.add("gleam/result");
    this.neededModules.add("skir_client/internal/unrecognized");
    const { typeSpeller } = this;
    const typeName =
      this.uniqueTypeNames.get(struct.record.key) ?? getTypeName(struct);
    const fnPrefix =
      struct.recordAncestors
        .map((a) => convertCase(a.name.text, "lower_underscore"))
        .join("__") + "_";
    // Sort fields by name for consistent output.
    const fields = [...struct.record.fields].sort((a, b) =>
      a.name.text.localeCompare(b.name.text),
    );

    this.pushSeparator(
      `struct ${struct.recordAncestors.map((r) => r.name.text).join(".")}`,
    );

    // Doc comment.
    this.push(commentify(docToCommentText(struct.record.doc)));

    // Determine which fields are hard-recursive (need Option wrapping).
    const hardRecFields = fields.filter((f) => f.isRecursive === "hard");

    // Type definition.
    // Hard-recursive fields are stored internally as option.Option(T) under the
    // label `fieldname_rec` to avoid infinite-size types.
    this.push(`pub type ${typeName} {\n`);
    this.push(`${typeName}(\n`);
    for (const field of fields) {
      const fieldName = toFieldName(field.name.text);
      this.push(commentify(docToCommentText(field.doc)));
      if (field.isRecursive === "hard") {
        const inner = typeSpeller.getGleamType(field.type!);
        this.push(`${fieldName}_rec: option_.Option(${inner}),\n`);
      } else {
        const gleamType = typeSpeller.getGleamType(field.type!);
        this.push(`${fieldName}: ${gleamType},\n`);
      }
    }
    // Trailing underscore avoids conflict with user-defined fields named `unrecognized`.
    this.push(
      `unrecognized_: unrecognized_.UnrecognizedFields(${typeName}),\n`,
    );
    this.push(")\n");
    this.push("}\n\n");

    // Getters for hard-recursive fields.
    // These expose a plain T (not Option(T)) to callers, returning the default
    // value when the stored Option is None.
    for (const field of hardRecFields) {
      const fieldName = toFieldName(field.name.text);
      const innerType = typeSpeller.getGleamType(field.type!);
      const defExpr = typeSpeller.getDefaultExpression(field.type!);
      this.push(commentify(docToCommentText(field.doc)));
      this.push(
        `pub fn ${fnPrefix}${fieldName}(s: ${typeName}) -> ${innerType} {\n`,
      );
      this.push(`case s.${fieldName}_rec {\n`);
      this.push(`option_.Some(v) -> v\n`);
      this.push(`option_.None -> ${defExpr}\n`);
      this.push("}\n");
      this.push("}\n\n");
    }

    // Default const or function.
    const useConstDefault = this.constDefaultKeys.has(struct.record.key);
    this.push(
      useConstDefault
        ? `/// The default \`${typeName}\` with all fields set to their default values.\n`
        : `/// Returns the default \`${typeName}\` with all fields set to their default values.\n`,
    );
    if (useConstDefault) {
      this.push(`pub const ${fnPrefix}default = ${typeName}(\n`);
    } else {
      this.push(`pub fn ${fnPrefix}default() -> ${typeName} {\n`);
      this.push(`${typeName}(\n`);
    }
    for (const field of fields) {
      const fieldName = toFieldName(field.name.text);
      if (field.isRecursive === "hard") {
        this.push(`${fieldName}_rec: option_.None,\n`);
      } else {
        const defExpr = typeSpeller.getDefaultExpression(field.type!);
        this.push(`${fieldName}: ${defExpr},\n`);
      }
    }
    this.push(`unrecognized_: option_.None,\n`);
    if (useConstDefault) {
      this.push(")\n\n");
    } else {
      this.push(")\n");
      this.push("}\n\n");
    }

    // `new` constructor function.
    this.push(
      `/// Creates a new \`${typeName}\` with the given field values.\n`,
    );
    this.push(`pub fn ${fnPrefix}new(\n`);
    for (const field of fields) {
      const fieldName = toFieldName(field.name.text);
      if (field.isRecursive === "hard") {
        const innerType = typeSpeller.getGleamType(field.type!);
        this.push(`${fieldName}: ${innerType},\n`);
      } else {
        const gleamType = typeSpeller.getGleamType(field.type!);
        this.push(`${fieldName}: ${gleamType},\n`);
      }
    }
    this.push(`) -> ${typeName} {\n`);
    this.push(`${typeName}(\n`);
    for (const field of fields) {
      const fieldName = toFieldName(field.name.text);
      if (field.isRecursive === "hard") {
        this.push(`${fieldName}_rec: option_.Some(${fieldName}),\n`);
      } else {
        this.push(`${fieldName}: ${fieldName},\n`);
      }
    }
    this.push(`unrecognized_: option_.None,\n`);
    this.push(`)\n`);
    this.push(`}\n\n`);

    // Serializer.
    const fieldsByNumber = [...struct.record.fields].sort(
      (a, b) => a.number - b.number,
    );

    const structDefaultExpr = `${fnPrefix}default${useConstDefault ? "" : "()"}`;

    this.push(`/// Returns the serializer for \`${typeName}\` values.\n`);
    this.push(
      `pub fn ${fnPrefix}serializer() -> skir_client_.Serializer(${typeName}) {\n`,
    );
    // Hoist non-recursive serializer construction so it is created once and
    // reused in ordered_fields, decode_dense_json, and decode_binary.
    for (const field of fieldsByNumber) {
      if (field.isRecursive === false) {
        const varName = toFieldName(field.name.text);
        const serExpr = typeSpeller.getSerializerExpression(field.type!);
        this.push(`let ${varName}_serializer = ${serExpr}\n`);
      }
    }
    this.push(`struct_serializer_.new_serializer(\n`);
    this.push(`name: ${JSON.stringify(struct.record.name.text)},\n`);
    this.push(
      `qualified_name: ${JSON.stringify(struct.recordAncestors.map((r) => r.name.text).join("."))},\n`,
    );
    this.push(`module_path: ${JSON.stringify(struct.modulePath)},\n`);
    this.push(`doc: ${JSON.stringify(docToCommentText(struct.record.doc))},\n`);
    this.push(`ordered_fields: [\n`);
    for (const field of fieldsByNumber) {
      const fieldName = toFieldName(field.name.text);
      const isHardRec = field.isRecursive === "hard";
      const isRecursive = field.isRecursive !== false;
      const fieldType = typeSpeller.getGleamType(field.type!);
      this.push(`struct_serializer_.field_spec_to_field_adapter(\n`);
      this.push(`name: ${JSON.stringify(field.name.text)},\n`);
      this.push(`number: ${field.number},\n`);
      this.push(`doc: ${JSON.stringify(docToCommentText(field.doc))},\n`);
      this.push(`default: ${typeSpeller.getDefaultExpression(field.type!)},\n`);
      this.push(
        `type_sig: ${typeSpeller.getTypeSignatureExpression(field.type!)},\n`,
      );
      if (isHardRec) {
        this.push(`get: fn(s: ${typeName}) { ${fnPrefix}${fieldName}(s) },\n`);
        this.push(
          `set: fn(s: ${typeName}, v: ${fieldType}) { ${typeName}(..s, ${fieldName}_rec: option_.Some(v)) },\n`,
        );
      } else {
        this.push(`get: fn(s: ${typeName}) { s.${fieldName} },\n`);
        this.push(
          `set: fn(s: ${typeName}, v: ${fieldType}) { ${typeName}(..s, ${fieldName}: v) },\n`,
        );
      }
      if (isRecursive) {
        this.push(`serializer: struct_serializer_.Lazy(fn() {\n`);
        this.push(`${typeSpeller.getSerializerExpression(field.type!)}\n`);
        this.push(`}),\n`);
      } else {
        this.push(
          `serializer: struct_serializer_.Eager(${fieldName}_serializer),\n`,
        );
      }
      this.push(`),\n`);
    }
    this.push(`],\n`);
    this.push(`default: ${structDefaultExpr},\n`);
    this.push(`get_unrecognized: fn(s) { s.unrecognized_ },\n`);
    const setUnrecognizedBody =
      struct.record.fields.length === 0
        ? `${typeName}(unrecognized_: u)`
        : `${typeName}(..s, unrecognized_: u)`;
    const setUnrecognizedArg = struct.record.fields.length === 0 ? `_s` : `s`;
    this.push(
      `set_unrecognized: fn(${setUnrecognizedArg}, u) { ${setUnrecognizedBody} },\n`,
    );
    this.push(
      `removed_numbers: [${struct.record.removedNumbers.join(", ")}],\n`,
    );
    this.push(
      `recognized_slot_count: ${struct.record.numSlotsInclRemovedNumbers},\n`,
    );

    // Generate decode_dense_json callback
    const numSlots = struct.record.numSlotsInclRemovedNumbers;
    const fieldsBySlot = new Map(fieldsByNumber.map((f) => [f.number, f]));

    this.push(`decode_dense_json: fn(arr, keep) {\n`);
    this.push(`let arr_len = list_.length(arr)\n`);
    for (let slot = 0; slot < numSlots; slot++) {
      const field = fieldsBySlot.get(slot);
      if (field) {
        const isHardRec = field.isRecursive === "hard";
        const varName = toFieldName(field.name.text);
        const defExpr = typeSpeller.getDefaultExpression(field.type!);
        const serExpr =
          field.isRecursive === false
            ? `${varName}_serializer`
            : typeSpeller.getSerializerExpression(field.type!);
        this.push(
          `let #(slot_${slot}_dyn, arr) = struct_serializer_.take_slot(arr)\n`,
        );
        if (isHardRec) {
          this.push(
            `use ${varName}_rec <- result_.try(struct_serializer_.decode_json_field_opt(slot_${slot}_dyn, keep, serializer: ${serExpr}))\n`,
          );
        } else {
          this.push(
            `use ${varName} <- result_.try(struct_serializer_.decode_json_field(slot_${slot}_dyn, ${defExpr}, keep, serializer: ${serExpr}))\n`,
          );
        }
      } else {
        this.push(`let #(_, arr) = struct_serializer_.take_slot(arr)\n`);
      }
    }
    this.push(
      `let unrecognized_ = struct_serializer_.make_unrecognized_fields_json(arr, arr_len, keep)\n`,
    );
    const fieldArgsDense = fieldsByNumber
      .map((f) => {
        const varName = toFieldName(f.name.text);
        return f.isRecursive === "hard" ? `${varName}_rec:` : `${varName}:`;
      })
      .join(", ");
    const structArgsDense =
      fieldArgsDense +
      (fieldsByNumber.length > 0 ? ", " : "") +
      "unrecognized_:";
    this.push(`Ok(${typeName}(${structArgsDense}))\n`);
    this.push(`},\n`);

    // Generate decode_binary callback
    const slotsToFillParam = numSlots > 0 ? "slots_to_fill" : "_slots_to_fill";
    const keepParam = fieldsByNumber.length > 0 ? "keep" : "_keep";
    this.push(`decode_binary: fn(bits, ${slotsToFillParam}, ${keepParam}) {\n`);
    for (let slot = 0; slot < numSlots; slot++) {
      const field = fieldsBySlot.get(slot);
      if (field) {
        const isHardRec = field.isRecursive === "hard";
        const varName = toFieldName(field.name.text);
        const defExpr = typeSpeller.getDefaultExpression(field.type!);
        const serExpr =
          field.isRecursive === false
            ? `${varName}_serializer`
            : typeSpeller.getSerializerExpression(field.type!);
        if (isHardRec) {
          this.push(
            `use #(${varName}_rec, bits) <- result_.try(struct_serializer_.decode_binary_field_opt(bits, slots_to_fill > ${slot}, keep, serializer: ${serExpr}))\n`,
          );
        } else {
          this.push(
            `use #(${varName}, bits) <- result_.try(struct_serializer_.decode_binary_field(bits, slots_to_fill > ${slot}, ${defExpr}, keep, serializer: ${serExpr}))\n`,
          );
        }
      } else {
        this.push(
          `use bits <- result_.try(struct_serializer_.skip_binary_slot(bits, slots_to_fill > ${slot}))\n`,
        );
      }
    }
    const fieldArgsBin = fieldsByNumber
      .map((f) => {
        const varName = toFieldName(f.name.text);
        return f.isRecursive === "hard" ? `${varName}_rec:` : `${varName}:`;
      })
      .join(", ");
    const structArgsBin =
      fieldArgsBin +
      (fieldsByNumber.length > 0 ? ", " : "") +
      "unrecognized_: option_.None";
    this.push(`Ok(#(${typeName}(${structArgsBin}), bits))\n`);
    this.push(`},\n`);

    this.push(`)\n`);
    this.push(`}\n\n`);
  }

  private writeTypesForEnum(record: RecordLocation): void {
    this.neededModules.add("gleam/option");
    this.neededModules.add("skir_client");
    this.neededModules.add("skir_client/internal/enum_serializer");
    this.neededModules.add("skir_client/internal/unrecognized");
    const { typeSpeller } = this;
    const typeName =
      this.uniqueTypeNames.get(record.record.key) ?? getTypeName(record);
    const fnPrefix =
      record.recordAncestors
        .map((a) => convertCase(a.name.text, "lower_underscore"))
        .join("__") + "_";
    const unknownCtorName =
      this.ctorNames.get(`${record.record.key}:__unknown__`) ??
      typeName + "Unknown";
    const variants = record.record.fields;

    this.pushSeparator(
      `enum ${record.recordAncestors.map((r) => r.name.text).join(".")}`,
    );

    // Doc comment.
    this.push(commentify(docToCommentText(record.record.doc)));

    // Type definition.
    // The Unknown variant is the only variant that may conflict with a
    // user-defined variant named "unknown"; this is documented as reserved.
    this.push(`pub type ${typeName} {\n`);
    this.push(
      `${unknownCtorName}(unrecognized_.UnrecognizedVariant(${typeName}))\n`,
    );
    for (const variant of variants) {
      const ctorName =
        this.ctorNames.get(`${record.record.key}:${variant.name.text}`) ??
        typeName + convertCase(variant.name.text, "UpperCamel");
      this.push(commentify(docToCommentText(variant.doc)));
      if (variant.type) {
        const gleamType = typeSpeller.getGleamType(variant.type);
        this.push(`${ctorName}(${gleamType})\n`);
      } else {
        this.push(`${ctorName}\n`);
      }
    }
    this.push("}\n\n");

    // Default const — an enum defaults to the Unknown variant.
    this.push(`/// The default \`${typeName}\` (the unknown variant).\n`);
    this.push(
      `pub const ${fnPrefix}unknown = ${unknownCtorName}(option_.None)\n\n`,
    );

    // Serializer.
    this.push(`/// Returns the serializer for \`${typeName}\` values.\n`);
    this.push(
      `pub fn ${fnPrefix}serializer() -> skir_client_.Serializer(${typeName}) {\n`,
    );
    this.push(`enum_serializer_.new_serializer(\n`);
    this.push(`name: ${JSON.stringify(record.record.name.text)},\n`);
    this.push(
      `qualified_name: ${JSON.stringify(record.recordAncestors.map((r) => r.name.text).join("."))},\n`,
    );
    this.push(`module_path: ${JSON.stringify(record.modulePath)},\n`);
    this.push(`doc: ${JSON.stringify(docToCommentText(record.record.doc))},\n`);
    this.push(`variants: [\n`);
    for (const [i, variant] of variants.entries()) {
      const ctorName =
        this.ctorNames.get(`${record.record.key}:${variant.name.text}`) ??
        typeName + convertCase(variant.name.text, "UpperCamel");
      if (!variant.type) {
        // Constant variant.
        this.push(`enum_serializer_.constant_variant(\n`);
        this.push(`name: ${JSON.stringify(variant.name.text)},\n`);
        this.push(`number: ${variant.number},\n`);
        this.push(`doc: ${JSON.stringify(docToCommentText(variant.doc))},\n`);
        this.push(`instance: ${ctorName},\n`);
        this.push(`),\n`);
      } else {
        // Wrapper variant.
        // Detect direct self-reference (recursive enum variant).
        const vType = variant.type!;
        const isDirectSelfRef =
          vType.kind === "record" && vType.key === record.record.key;
        this.push(`enum_serializer_.wrapper_variant(\n`);
        this.push(`name: ${JSON.stringify(variant.name.text)},\n`);
        this.push(`number: ${variant.number},\n`);
        this.push(`doc: ${JSON.stringify(docToCommentText(variant.doc))},\n`);
        this.push(`serializer: fn() {\n`);
        this.push(`${typeSpeller.getSerializerExpression(variant.type)}\n`);
        this.push(`},\n`);
        if (isDirectSelfRef) {
          this.push(
            `type_sig: option_.Some(${typeSpeller.getTypeSignatureExpression(vType)}),\n`,
          );
        } else {
          this.push(`type_sig: option_.None,\n`);
        }
        this.push(`wrap: fn(v) { ${ctorName}(v) },\n`);
        this.push(`unwrap: fn(e) { let assert ${ctorName}(v) = e\n v },\n`);
        this.push(`),\n`);
      }
      void i;
    }
    this.push(`],\n`);
    this.push(`unknown_default: ${fnPrefix}unknown,\n`);
    this.push(`get_kind_ordinal: fn(e) {\n`);
    this.push(`case e {\n`);
    this.push(`${unknownCtorName}(_) -> 0\n`);
    for (const [i, variant] of variants.entries()) {
      const ctorName =
        this.ctorNames.get(`${record.record.key}:${variant.name.text}`) ??
        typeName + convertCase(variant.name.text, "UpperCamel");
      const pattern = variant.type ? `${ctorName}(_)` : ctorName;
      this.push(`${pattern} -> ${i + 1}\n`);
    }
    this.push(`}\n`);
    this.push(`},\n`);
    this.push(`wrap_unrecognized: fn(u) { ${unknownCtorName}(u) },\n`);
    this.push(`get_unrecognized: fn(e) {\n`);
    this.push(`case e {\n`);
    this.push(`${unknownCtorName}(u) -> u\n`);
    if (variants.length > 0) {
      this.push(`_ -> option_.None\n`);
    }
    this.push(`}\n`);
    this.push(`},\n`);
    this.push(
      `removed_numbers: [${record.record.removedNumbers.join(", ")}],\n`,
    );
    this.push(`)\n`);
    this.push(`}\n\n`);
  }

  private pushSeparator(header: string): void {
    this.push(`// ${"=".repeat(78)}\n`);
    this.push(`// ${header}\n`);
    this.push(`// ${"=".repeat(78)}\n\n`);
  }

  private push(...code: string[]): void {
    this.code += code.join("");
  }

  private joinLinesAndFixFormatting(): string {
    const indentUnit = "  ";
    let result = "";
    // The indent at every line is obtained by repeating indentUnit N times,
    // where N is the length of this array.
    const contextStack: Array<"{" | "(" | "[" | "<" | ":" | "."> = [];
    // Returns the last element in `contextStack`.
    const peakTop = (): string => contextStack.at(-1)!;
    const getMatchingLeftBracket = (r: "}" | ")" | "]" | ">"): string => {
      switch (r) {
        case "}":
          return "{";
        case ")":
          return "(";
        case "]":
          return "[";
        case ">":
          return "<";
      }
    };
    for (let line of this.code.split("\n")) {
      line = line.trim();
      if (line.length <= 0) {
        // Don't indent empty lines.
        result += "\n";
        continue;
      }

      const firstChar = line[0];
      switch (firstChar) {
        case "}":
        case ")":
        case "]":
        case ">": {
          const left = getMatchingLeftBracket(firstChar);
          while (contextStack.pop() !== left) {
            if (contextStack.length <= 0) {
              throw Error();
            }
          }
          break;
        }
        case ".": {
          if (peakTop() !== ".") {
            contextStack.push(".");
          }
          break;
        }
      }
      let indent = indentUnit.repeat(contextStack.length);
      if (line.startsWith("*")) {
        // Docstring: make sure the stars are aligned.
        indent += " ";
      }
      result += `${indent}${line}\n`;
      if (line.startsWith("//")) {
        continue;
      }
      const lastChar = line.slice(-1);
      switch (lastChar) {
        case "{":
        case "(":
        case "[":
        case "<": {
          // The next line will be indented
          contextStack.push(lastChar);
          break;
        }
        case ":":
        case "=": {
          if (peakTop() !== ":") {
            contextStack.push(":");
          }
          break;
        }
        case ";":
        case ",": {
          if (peakTop() === "." || peakTop() === ":") {
            contextStack.pop();
          }
        }
      }
    }

    return (
      result
        // Remove spaces enclosed within curly brackets if that's all there is.
        .replace(/\{\s+\}/g, "{}")
        // Remove spaces enclosed within round brackets if that's all there is.
        .replace(/\(\s+\)/g, "()")
        // Remove spaces enclosed within square brackets if that's all there is.
        .replace(/\[\s+\]/g, "[]")
        // Remove empty line following an open curly bracket.
        .replace(/(\{\n *)\n/g, "$1")
        // Remove empty line preceding a closed curly bracket.
        .replace(/\n(\n *\})/g, "$1")
        // Coalesce consecutive empty lines.
        .replace(/\n\n\n+/g, "\n\n")
        .replace(/\n\n$/g, "\n")
    );
  }
}

export const GENERATOR = new GleamCodeGenerator();

function commentify(text: string): string {
  const trimmed = text.trim().replace(/\n{3,}/g, "\n\n");
  if (trimmed.length <= 0) {
    return "";
  }
  return trimmed
    .split("\n")
    .map((line) => (line.length > 0 ? `/// ${line}\n` : `///\n`))
    .join("");
}

function docToCommentText(doc: Doc): string {
  return doc.pieces
    .map((p) => {
      switch (p.kind) {
        case "text":
          return p.text;
        case "reference":
          return "`" + p.referenceRange.text.slice(1, -1) + "`";
      }
    })
    .join("");
}
