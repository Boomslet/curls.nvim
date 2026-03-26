; Encore.ts: export const name = api({ method: "X", path: "/y" }, async (p: T) => ...)
(export_statement
  declaration: (lexical_declaration
    (variable_declarator
      name: (identifier) @endpoint.name
      value: (call_expression
        function: (identifier) @_fn (#eq? @_fn "api")
        arguments: (arguments
          (object) @endpoint.config
          (_) @endpoint.handler)))))

; Encore.ts raw: export const name = api.raw({ ... }, async (req, resp) => ...)
(export_statement
  declaration: (lexical_declaration
    (variable_declarator
      name: (identifier) @endpoint.name
      value: (call_expression
        function: (member_expression
          object: (identifier) @_fn2 (#eq? @_fn2 "api")
          property: (property_identifier) @endpoint.variant)
        arguments: (arguments
          (object) @endpoint.config
          (_) @endpoint.handler)))))
