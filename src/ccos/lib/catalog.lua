-- Shared category and tool registry. Each entry maps to a real implementation.
local C = { categories = { "Favorites", "Files", "Time", "Media", "Math", "Text", "Developer", "System", "Games", "AI" } }
C.base = { files="Files", viewer="Files", terminal="Developer", edit="Developer", lua="Developer", paint="Media",
  music="Media", piano="Media", clock="Time", calc="Math", print="Files", tasks="System", settings="System", about="System", worm="Games", agent="AI" }
C.tools = {
  {"notes","Notes","Create and save text notes","Files"},
  {"checklist","Checklist","Persistent tasks and checkboxes","Files"},
  {"journal","Journal","Dated entries in your own files","Files"},
  {"bookmarks","Bookmarks","Save paths and web addresses","Files"},
  {"calendar","Calendar","Browse months and weekdays","Time"},
  {"worldclock","World clocks","Live clocks across time zones","Time"},
  {"focus","Focus timer","Work and break sessions","Time"},
  {"stopwatch","Stopwatch","Start, lap, stop and reset","Time"},
  {"timer","Countdown","Adjustable countdown with alarm","Time"},
  {"units","Unit converter","Length, mass, temperature and data","Math"},
  {"percentage","Percentages","Percentage, change and proportions","Math"},
  {"base","Base converter","Binary, decimal and hexadecimal","Math"},
  {"random","Random numbers","Choose a range and draw a number","Math"},
  {"dice","Dice","Roll one or several dice","Games"},
  {"coin","Coin flip","Heads or tails and running totals","Games"},
  {"tally","Counter","Count, decrement and reset","Math"},
  {"textstats","Text statistics","Words, lines, bytes and characters","Text"},
  {"textcase","Change case","Upper, lower and title case","Text"},
  {"lines","Line tools","Sort, reverse and deduplicate lines","Text"},
  {"replace","Find & replace","Literal text replacement and save","Text",false},
  {"urlencode","URL encoder","Encode and decode URL components","Text"},
  {"base64","Base64","Encode and decode text","Text"},
  {"json","JSON tools","Validate, inspect and format JSON","Developer"},
  {"http","HTTP inspector","GET a URL and inspect its response","Developer",false},
  {"network","Network monitor","Inspect modems and incoming messages","Developer"},
  {"redstone","Redstone","Digital inputs and output switches","System"},
  {"analog","Analog signals","Read and adjust redstone levels","System"},
  {"bundled","Bundled signals","Toggle the sixteen color channels","System"},
  {"peripherals","Peripherals","Names, types and supported methods","System"},
  {"inventory","Inventories","Inspect connected item inventories","System"},
  {"energy","Energy stores","Stored energy and capacity","System"},
  {"fluids","Fluid tanks","Inspect connected fluid stores","System"},
  {"disks","Disk manager","Browse, label and eject disks","Files"},
  {"storage","Storage analyzer","Folder sizes and free space","Files"},
  {"backup","Backups","Back up and restore user data","Files"},
  {"logs","Log viewer","Read OS and agent activity logs","Developer"},
  {"sysinfo","System info","Runtime, storage and attached hardware","System"},
  {"display","Displays","Roles, scale and monitor sizes","System"},
  {"palette","Theme gallery","Preview and apply system themes","System"},
  {"soundtest","Speaker test","Test stereo channels and instruments","Media"},
  {"metronome","Metronome","Adjust tempo and count beats","Media"},
  {"lights","Lights Out","Clear the grid by toggling neighbors","Games"},
  {"memory","Memory pairs","Find the matching pairs","Games"},
  {"tictactoe","Tic-tac-toe","Two-player three-in-a-row","Games"},
  {"guess","Guess the number","Find the hidden number using clues","Games"},
}
function C.apps()
  local list = {}
  for _, t in ipairs(C.tools) do
    list[#list+1] = { id=t[1], name=t[2], desc=t[3], category=t[4], touch=t[5] ~= false,
      path="tools", tool=t[1], w=72, h=24 }
  end
  return list
end
return C
