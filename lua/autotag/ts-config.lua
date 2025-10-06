---@class AutoTag.TSConfig
---@field opening_node_types string[]
---@field identifier_node_types string[]
---@field closing_node_types string[]

---@type AutoTag.TSConfig
return {
  opening_node_types = {
    -- html
    "start_tag",
    -- xml,
    "STag",
    -- templ
    "tag_start",
    -- jsx
    "jsx_opening_element",
  },

  identifier_node_types = {
    -- html
    "tag_name",
    "erroneous_end_tag_name",
    -- xml,
    "Name",
    -- templ
    "element_identifier",
    -- jsx
    "member_expression",
    "identifier",
  },

  closing_node_types = {
    -- html
    "end_tag",
    "erroneous_end_tag",
    -- xml,
    "ETag",
    -- templ
    "tag_end",
    -- jsx
    "jsx_closing_element",
  }
}
