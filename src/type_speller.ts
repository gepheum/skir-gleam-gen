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
            this.neededModules.add("timestamp");
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
    this.neededModules.add("serializers");
    switch (type.kind) {
      case "primitive": {
        switch (type.primitive) {
          case "bool":
            return "serializers_.bool_serializer()";
          case "int32":
            return "serializers_.int32_serializer()";
          case "int64":
            return "serializers_.int64_serializer()";
          case "hash64":
            return "serializers_.hash64_serializer()";
          case "float32":
            return "serializers_.float32_serializer()";
          case "float64":
            return "serializers_.float64_serializer()";
          case "timestamp":
            return "serializers_.timestamp_serializer()";
          case "string":
            return "serializers_.string_serializer()";
          case "bytes":
            return "serializers_.bytes_serializer()";
        }
        const _: never = type.primitive;
        throw TypeError();
      }
      case "array": {
        const itemSerializer = this.getSerializerExpression(type.item);
        if (type.key) {
          const keyExtractor = type.key.path.map((p) => p.name.text).join(".");
          return (
            "serializers_.keyed_list_serializer(\n" +
            itemSerializer +
            ",\n" +
            JSON.stringify(keyExtractor) +
            ",\n)"
          );
        } else {
          return "serializers_.list_serializer(\n" + itemSerializer + ",\n)";
        }
      }
      case "optional":
        return (
          "serializers_.optional_serializer(\n" +
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
            this.neededModules.add("timestamp");
            return "timestamp_.Timestamp(unix_millis: 0)";
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
    this.neededModules.add("type_descriptor");
    switch (type.kind) {
      case "primitive": {
        const prim = (
          {
            bool: "type_descriptor_.Bool",
            int32: "type_descriptor_.Int32",
            int64: "type_descriptor_.Int64",
            hash64: "type_descriptor_.Hash64",
            float32: "type_descriptor_.Float32",
            float64: "type_descriptor_.Float64",
            timestamp: "type_descriptor_.Timestamp",
            string: "type_descriptor_.StringType",
            bytes: "type_descriptor_.Bytes",
          } as const
        )[type.primitive];
        return `type_descriptor_.Primitive(${prim})`;
      }
      case "record": {
        const rec = this.recordMap.get(type.key)!;
        const qualifiedName = rec.recordAncestors
          .map((a) => a.name.text)
          .join(".");
        const id = `${rec.modulePath}:${qualifiedName}`;
        return `type_descriptor_.Record(${JSON.stringify(id)})`;
      }
      case "array": {
        const itemSig = this.getTypeSignatureExpression(type.item);
        const keyExtractor =
          type.key?.path.map((p) => p.name.text).join(".") ?? "";
        return `type_descriptor_.Array(${itemSig}, ${JSON.stringify(keyExtractor)})`;
      }
      case "optional": {
        return `type_descriptor_.Optional(${this.getTypeSignatureExpression(type.other)})`;
      }
    }
  }
}
