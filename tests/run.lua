local root = arg[0]:match("^(.*)/tests/run%.lua$") or "."
package.path = root .. "/src/?.lua;" .. root .. "/tests/lua/?.lua;" .. package.path

local total, failed = 0, 0
function test(name, fn)
  total = total + 1
  local ok, err = pcall(fn)
  if ok then print("ok " .. total .. " - " .. name) else failed = failed + 1; print("not ok " .. total .. " - " .. name .. "\n  " .. tostring(err)) end
end
function eq(actual, expected)
  if actual ~= expected then error("expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

dofile(root .. "/tests/lua/test_command_parser.lua")
dofile(root .. "/tests/lua/test_game_clock.lua")
dofile(root .. "/tests/lua/test_command_collector.lua")
dofile(root .. "/tests/lua/test_navigation.lua")
dofile(root .. "/tests/lua/test_mapper_model.lua")
dofile(root .. "/tests/lua/test_special_transition.lua")
dofile(root .. "/tests/lua/test_map_adapter.lua")
dofile(root .. "/tests/lua/test_map_transfer.lua")
dofile(root .. "/tests/lua/test_map_catalog.lua")
dofile(root .. "/tests/lua/test_map_collections.lua")
dofile(root .. "/tests/lua/test_map_cleanup.lua")
dofile(root .. "/tests/lua/test_map_diagnostics.lua")
dofile(root .. "/tests/lua/test_failure_report.lua")
dofile(root .. "/tests/lua/test_feedback_submission.lua")
dofile(root .. "/tests/lua/test_automapper.lua")
dofile(root .. "/tests/lua/test_map_walker.lua")
dofile(root .. "/tests/lua/test_state.lua")
dofile(root .. "/tests/lua/test_settings.lua")
dofile(root .. "/tests/lua/test_sha256.lua")
dofile(root .. "/tests/lua/test_release.lua")
dofile(root .. "/tests/lua/test_runtime.lua")
dofile(root .. "/tests/lua/test_updater.lua")
dofile(root .. "/tests/lua/test_layout.lua")
dofile(root .. "/tests/lua/test_view.lua")
dofile(root .. "/tests/lua/test_chat_parser.lua")
dofile(root .. "/tests/lua/test_chat_history.lua")
dofile(root .. "/tests/lua/test_chat_storage.lua")
dofile(root .. "/tests/lua/test_chat_controller.lua")
dofile(root .. "/tests/lua/test_output_colorizer.lua")
dofile(root .. "/tests/lua/test_posture_tracker.lua")
dofile(root .. "/tests/lua/test_autoroller.lua")
dofile(root .. "/tests/lua/test_chat_acceptance.lua")
dofile(root .. "/tests/lua/test_mapper_acceptance.lua")
dofile(root .. "/tests/lua/test_entry.lua")

print(string.format("%d tests, %d failures", total, failed))
os.exit(failed == 0 and 0 or 1)
