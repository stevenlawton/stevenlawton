-- Abridged CV variant filter. Chains BEFORE wrap-experience.lua.
-- Derives the short CV from the single CV.md source by:
--   * dropping the entire "Open Source & Personal Projects" section
--   * keeping only the first N roles under "Experience"
--     (N from -M abridged_roles, default 3)
-- Every other block passes through unchanged, so Summary, Skills, the
-- trimmed Experience, Why Me? and Contact are all retained.
local DROP_SECTIONS = { ["Open Source & Personal Projects"] = true }

return {
  {
    Pandoc = function(doc)
      local keep = 3
      if doc.meta.abridged_roles then
        keep = tonumber(pandoc.utils.stringify(doc.meta.abridged_roles)) or keep
      end

      local out = {}
      local dropping = false       -- inside a dropped level-2 section
      local in_experience = false  -- inside the Experience section
      local role_count = 0
      local skip_role = false      -- dropping an excess role's content

      for _, el in ipairs(doc.blocks) do
        if el.t == "Header" and el.level == 2 then
          local title = pandoc.utils.stringify(el.content)
          dropping = DROP_SECTIONS[title] == true
          in_experience = (title == "Experience")
          role_count = 0
          skip_role = false
          if not dropping then table.insert(out, el) end
        elseif dropping then
          -- skip everything until the next level-2 header
        elseif in_experience and el.t == "Header" and el.level == 3 then
          role_count = role_count + 1
          skip_role = role_count > keep
          if not skip_role then table.insert(out, el) end
        elseif in_experience and skip_role then
          -- skip content blocks of excess roles
        else
          table.insert(out, el)
        end
      end

      return pandoc.Pandoc(out, doc.meta)
    end
  }
}
