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
        return `option.Option(${this.getGleamType(type.other)})`;
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
            return "timestamp.Timestamp";
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
    switch (type.kind) {
      case "primitive": {
        switch (type.primitive) {
          case "bool":
            return "skir_client.bool_serializer()";
          case "int32":
            return "skir_client.int32_serializer()";
          case "int64":
            return "skir_client.int64_serializer()";
          case "hash64":
            return "skir_client.hash64_serializer()";
          case "float32":
            return "skir_client.float32_serializer()";
          case "float64":
            return "skir_client.float64_serializer()";
          case "timestamp":
            return "skir_client.timestamp_serializer()";
          case "string":
            return "skir_client.string_serializer()";
          case "bytes":
            return "skir_client.bytes_serializer()";
        }
        const _: never = type.primitive;
        throw TypeError();
      }
      case "array": {
        const itemSerializer = this.getSerializerExpression(type.item);
        if (type.key) {
          const keyExtractor = type.key.path.map((p) => p.name.text).join(".");
          return (
            "skir_client.keyed_list_serializer(\n" +
            itemSerializer +
            ",\n" +
            JSON.stringify(keyExtractor) +
            ",\n)"
          );
        } else {
          return "skir_client.list_serializer(\n" + itemSerializer + ",\n)";
        }
      }
      case "optional":
        return (
          "skir_client.optional_serializer(\n" +
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
        return "option.None";
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
            return "timestamp.from_unix_seconds_and_nanoseconds(0, 0)";
          case "bytes":
            return "<<>>";
        }
        const _: never = type.primitive;
        throw TypeError();
      }
    }
  }
}
