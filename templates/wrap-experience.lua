-- Wrap each level-3 sub-section (heading + its content) under selected
-- level-2 sections into a Div, so the print CSS can keep each role/project
-- from being split across a page boundary (page-break-inside: avoid).
--
-- Pandoc's html5 writer renders a single-class Div as <section class="...">
-- and derives the id from the enclosed heading, so the CSS rules
-- `section.experience` / `section.project` match automatically.
--
-- To add another section, map its exact level-2 heading text to a class and
-- add a matching print rule in templates/template.cv.html.html.
local section_class = {
  ["Experience"] = "experience",
  ["Open Source & Personal Projects"] = "project",
}

return {
  {
    Pandoc = function(doc)
      local final_blocks = {}
      local wrapped = {}         -- completed sub-sections for the active section
      local current_role = {}    -- blocks of the sub-section being accumulated
      local active_class = nil   -- class for the active level-2 section, or nil

      local function flush_role()
        if #current_role > 0 then
          table.insert(wrapped, pandoc.Div(current_role, pandoc.Attr("", {active_class})))
          current_role = {}
        end
      end

      local function flush_section()
        flush_role()
        for _, block in ipairs(wrapped) do
          table.insert(final_blocks, block)
        end
        wrapped = {}
        active_class = nil
      end

      for _, el in ipairs(doc.blocks) do
        if el.t == "Header" and el.level == 2 then
          -- New top-level section: flush the previous one, then decide whether
          -- this one is a section we wrap.
          if active_class then flush_section() end
          table.insert(final_blocks, el)
          active_class = section_class[pandoc.utils.stringify(el.content)]
        elseif active_class and el.t == "Header" and el.level == 3 then
          -- New role/project inside a wrapped section.
          flush_role()
          current_role = {el}
        elseif active_class then
          -- Content belonging to the current role/project.
          table.insert(current_role, el)
        else
          table.insert(final_blocks, el)
        end
      end

      flush_section()

      return pandoc.Pandoc(final_blocks, doc.meta)
    end
  }
}
