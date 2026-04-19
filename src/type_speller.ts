import type { RecordKey, RecordLocation, ResolvedType } from "skir-internal";

/**
 * Transforms a type found in a `.skir` file into Gleam type strings and expressions.
 *
 * Cross-module and same-module references are fully resolved via the callbacks
 * provided to the constructor. Callers (GleamSourceFileGenerator) build the
 * correct callbacks based on the current SCC group and the global keyToGroup map.
 */
export class TypeSpeller {
  constructor(
    readonly recordMap: ReadonlyMap<RecordKey, RecordLocation>,
    /** Returns the Gleam type expression for a record reference (with or without module alias). */
    private readonly typeExprFor: (key: RecordKey) => string,
    /** Returns the Gleam default() call expression for a record reference. */
    private readonly defaultExprFor: (key: RecordKey) => string,
    /** Returns the Gleam serializer() call expression for a record reference. */
    private readonly serializerExprFor: (key: RecordKey) => string,
    /** Accumulates the set of Gleam module paths that this speller references. */
    private readonly neededModules: Set<string>,
  ) {}

  /**
   * Returns the Gleam type string for the given resolved type.
   */
  getGleamType(type: ResolvedType): string {
    switch (type.kind) {
      case "record":
        return this.typeExprFor(type.key);
      case "array":
        return `List(${this.getGleamType(type.item)})`;
      case "optional":
        this.neededModules.add("gleam/option");
        return `option_.Option(${this.getGleamType(type.other)})`;
      case "primitive": {
        switch (type.primitive) {
          case "bool":
            return "Bool";
          case "int32":
          case "int64":
          case "hash64":
            return "Int";
          case "float32":
          case "float64":
            return "Float";
          case "string":
            return "String";
          case "timestamp":
            this.neededModules.add("gleam/time/timestamp");
            return "timestamp_.Timestamp";
          case "bytes":
            return "BitArray";
        }
        const _: never = type.primitive;
        throw TypeError();
      }
    }
  }

  /**
   * Returns the Gleam serializer expression for the given type.
   */
  getSerializerExpression(type: ResolvedType): string {
    this.neededModules.add("skir_client");
    switch (type.kind) {
      case "primitive": {
        switch (type.primitive) {
          case "bool":
            return "skir_client_.bool_serializer()";
          case "int32":
            return "skir_client_.int32_serializer()";
          case "int64":
            return "skir_client_.int64_serializer()";
          case "hash64":
            return "skir_client_.hash64_serializer()";
          case "float32":
            return "skir_client_.float32_serializer()";
          case "float64":
            return "skir_client_.float64_serializer()";
          case "timestamp":
            return "skir_client_.timestamp_serializer()";
          case "string":
            return "skir_client_.string_serializer()";
          case "bytes":
            return "skir_client_.bytes_serializer()";
        }
        const _: never = type.primitive;
        throw TypeError();
      }
      case "array": {
        const itemSerializer = this.getSerializerExpression(type.item);
        if (type.key) {
          const keyExtractor = type.key.path.map((p) => p.name.text).join(".");
          return (
            "skir_client_.keyed_list_serializer(\n" +
            itemSerializer +
            ",\n" +
            JSON.stringify(keyExtractor) +
            ",\n)"
          );
        } else {
          return "skir_client_.list_serializer(\n" + itemSerializer + ",\n)";
        }
      }
      case "optional":
        return (
          "skir_client_.optional_serializer(\n" +
          this.getSerializerExpression(type.other) +
          ",\n)"
        );
      case "record":
        return this.serializerExprFor(type.key);
    }
  }

  /**
   * Returns the Gleam default expression for the given type.
   */
  getDefaultExpression(type: ResolvedType): string {
    switch (type.kind) {
      case "record":
        return this.defaultExprFor(type.key);
      case "array":
        return "[]";
      case "optional":
        this.neededModules.add("gleam/option");
        return "option_.None";
      case "primitive": {
        switch (type.primitive) {
          case "bool":
            return "False";
          case "int32":
          case "int64":
          case "hash64":
            return "0";
          case "float32":
          case "float64":
            return "0.0";
          case "string":
            return '""';
          case "timestamp":
            this.neededModules.add("gleam/time/timestamp");
            return "timestamp_.from_unix_seconds_and_nanoseconds(0, 0)";
          case "bytes":
            return "<<>>";
        }
        const _: never = type.primitive;
        throw TypeError();
      }
    }
  }

  /**
   * Returns the Gleam expression for the TypeSignature of the given type.
   * Used to populate the `type_sig` field of FieldSpec for recursive fields.
   */
  getTypeSignatureExpression(type: ResolvedType): string {
    this.neededModules.add("skir_client");
    switch (type.kind) {
      case "primitive": {
        const prim = (
          {
            bool: "skir_client_.prim_bool()",
            int32: "skir_client_.prim_int32()",
            int64: "skir_client_.prim_int64()",
            hash64: "skir_client_.prim_hash64()",
            float32: "skir_client_.prim_float32()",
            float64: "skir_client_.prim_float64()",
            timestamp: "skir_client_.prim_timestamp()",
            string: "skir_client_.prim_string()",
            bytes: "skir_client_.prim_bytes()",
          } as const
        )[type.primitive];
        return `skir_client_.type_sig_primitive(${prim})`;
      }
      case "record": {
        const rec = this.recordMap.get(type.key)!;
        const qualifiedName = rec.recordAncestors
          .map((a) => a.name.text)
          .join(".");
        const id = `${rec.modulePath}:${qualifiedName}`;
        return `skir_client_.type_sig_record(${JSON.stringify(id)})`;
      }
      case "array": {
        const itemSig = this.getTypeSignatureExpression(type.item);
        const keyExtractor =
          type.key?.path.map((p) => p.name.text).join(".") ?? "";
        return `skir_client_.type_sig_array(${itemSig}, ${JSON.stringify(keyExtractor)})`;
      }
      case "optional": {
        return `skir_client_.type_sig_optional(${this.getTypeSignatureExpression(type.other)})`;
      }
    }
  }
}
