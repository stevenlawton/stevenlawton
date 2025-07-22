local in_experience = false
local experience_blocks = {}
local current_role = {}
local final_blocks = {}

return {
  {
    Pandoc = function(doc)
      for _, el in ipairs(doc.blocks) do
        if el.t == "Header" then
          local text = pandoc.utils.stringify(el.content)

          -- Start of Experience section
          if el.level == 2 and text == "Experience" then
            in_experience = true
            table.insert(final_blocks, el)
          -- New top-level section: flush roles and exit
          elseif in_experience and el.level == 2 then
            if #current_role > 0 then
              table.insert(experience_blocks, pandoc.Div(current_role, pandoc.Attr("", {"experience"})))
              current_role = {}
            end
            for _, block in ipairs(experience_blocks) do
              table.insert(final_blocks, block)
            end
            experience_blocks = {}
            in_experience = false
            table.insert(final_blocks, el)
          -- New job/role inside Experience
          elseif in_experience and el.level == 3 then
            if #current_role > 0 then
              table.insert(experience_blocks, pandoc.Div(current_role, pandoc.Attr("", {"experience"})))
            end
            current_role = {el}
          else
            if in_experience then
              table.insert(current_role, el)
            else
              table.insert(final_blocks, el)
            end
          end
        else
          if in_experience then
            table.insert(current_role, el)
          else
            table.insert(final_blocks, el)
          end
        end
      end

      -- Flush anything still pending
      if in_experience and #current_role > 0 then
        table.insert(experience_blocks, pandoc.Div(current_role, pandoc.Attr("", {"experience"})))
      end
      for _, block in ipairs(experience_blocks) do
        table.insert(final_blocks, block)
      end

      return pandoc.Pandoc(final_blocks, doc.meta)
    end
  }
}
