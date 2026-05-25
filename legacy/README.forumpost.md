Applies to all game modes:
Medkit (and [L4D2] Defibrillator) usage forces team score reduction for the rest of the map.
Friendly fire cooldown modes: general and player specific.
Melee kills are counted but (currently) not awarded.
Point losses are given from bot related actions (friendly fire a bot controlled team mate.)
Friendly fire damage based point loss. Formula: sm_l4dstats_ffire_multiplier * Damage. Keep in mind that there is also a multiplier for Advanced (2) and Expert (4) difficulty that is added to the score. If you play Co-op on Expert, and hit a friendly with damage of 10, you would normally be fined 4 * 25 = 100 points. If this feature is enabled and the multiplier was 2.0, you would be fined 4 * 2 * 10 = 80. If you would hit friendlies with damage of 20, you would be fined 160 points.
Crown a Witch and [L4D2] Level a Charge (kill a charging Charger with a melee weapon) awards.
New client commands: (usage same as "rank" and "top10")
nextrank - Show how many points is needed for gaining a rank.
top10ppm - Show Top10 Points Per Minute players.
showrank - Show player ranks from currently playing players.
showppm - Show player Points Per Minute from currently playing players.
showtimer - Show timer (Timed Maps).
rankvote - Initiate vote for shuffling teams based on their Points Per Minute ratio. More details below.
timedmaps - Show all map times (Timed Maps).
maptimes - Show current map times (Timed Maps).
rankmenu - Show rank menu.
rankmutetoggle - Toggle mute/unmute Custom Player Stats.
showmotd - Show the message of the day.

Applies to Versus and [L4D2] Scavenge modes:
General infected score:
Direct damage done by a special infected.
External damage (damage done by normal zombies while under the influence of a special zombie - boomer blindness / smoker choke / hunter lunge / [L4D2] jockey ride / [L4D2] charger plummel and carry - is forwarded to the special infected.)
Direct Incapacitate and Kill a survivor.
External Incapacitate and Kill a survivor.
Award from causing a survivor to grab a ledge.
Infected team penalty from letting survivors reach a saferoom and loosing a campaign finale.
Boomer blindness and award from a Perfect Blindness (default 4 survivors.)
Hunter award from Pain From Above (default damage >= 15) and Death From Above (default damage >= 25) pounces.
Tank Sniper (hit a survivor with a rock) and Bulldozer (default damage >= 200.)
Charger Scattering Ram (default 4 survivors.)

Applies to L4D2:
Penalty to whole survivor team for a triggering car alarm.
Earn points by giving Adrenaline or reviving player with a defibrillator.
Earn points by successfully pouring a gas canister.
Earn points by deploying an ammo upgrade.

[L4D2] Realism Support Explained:

As far as I know, the Realism gamemode is nothing more but tougher Co-op gamemode. The support only adds a multiplier to the score a player would gather from the same action in Co-op. My randomly selected default value for Realism score multiplier is 1.5. You can change this value and find the best possible value with the CVAR that controls it (read below).


[L4D2] Team Versus Support Explained:

As far as I know (again), the Team Versus gamemode is same as Versus. For this reason, the support only means that any game played in Team Versus gamemode, will be stored as Versus gamemode. To be more accurate, it means all the points earned playing Team Versus or Versus are mixed and both are read as Versus.


Survival Support Explained:

Players earn the normal score from killing the infected. Server administrators can set a CVAR to enable/disable score earned from health related actions. The Survival maps are filled with medical resources and I thought it's too easy to score points using the meds. I will put some more effort in to this gamemode soon...


[L4D2] Scavenge and Team Scavenge Support Explained:

In current state the plugin simply stores normal statistics. I will put some more effort in to this gamemode soon...


Timed Maps Explained:

All single team gamemodes record time of each map. This feature is currently not used in anything Rank related, only for statistical information. Unlike all other gamemodes, Survival will store the longest times instead of shortest times. I will put some more effort in to this feature and will add a panel for the players to view top times per map and their own times as well... soon...


Rank Vote Explained:

Rank Vote feature work only in two teams gamemodes: Versus and [L4D2] Scavenge. Note that L4D2 Team gamemodes are not supported! Each player can initiate a vote to shuffle teams by player PPM (Points Per Minute). A passing vote requires more that 50% of YES votes, so exactly half is not enough. When a Rank Vote passes, teams are set so that the highest ranking (PPM) player remains in the original team. Then the next player at PPM ranking is put to the opposite team, and the next to the highest ranking players team, and so on. This hopefully will lead to more equal teams. Read Quick installation guide for important information regarding Rank Vote!


LAN Support Explained:

When playing in LAN (sv_lan = 1) the stats are recorded with IP as player identity. Warning! This feature is highly unreliable because IP addresses are not necessarily static and individual. The webstats don't fully support the IP based stats and some links may not work as specified.


Message Of The Day Explained:

A server administrator can leave a Message Of The Day using console command sm_rank_motd. This MOTD is then shown at the web stats page. I have planned to send this value to everyone joining the game server. As of today, it is not yet done.
Tip: Edit your game server file motd.txt to have your web stats motd.php page.


Webstats Templates Explained:

Webstats can contain multiple templates. An easy example: Add a directory in templates and copy statstooltip.js from default to the new directory. Then edit the copied statstooltip.js color settings. Finally when all modifications are done, edit you config.php template and set the variable $site_template to contain the added directory name. I have included a demo template in the package, so you get the idea. If you can come up with something neat, send me a copy and I'll add it to the package!


Sound Effects Explained:

Plugin will play sound effects on certain events. All of the sound are included in the game installation. You can mute the plugin by modifying CVAR #55. Here is a list of events and what sound are played when the event occurs: (Sounds may vary on L4D1 and L4D2)
Map timer start (Timed Maps) - Short ticking sound.
Improve previous personal map time (Timed Maps) - Bell sound.
Rankvote gets passed and teams are shuffled - "Teleportation" sound.
Rankmenu opens.
I.e. successful Boomer Perfect Blindness or Hunter Death From Above.

Web Stats Player Country Flags and Location Explained:

If you want to see what country and city are your players from, you can do so by modifying your config.php. Read the installation instructions from the config.php file. Player country and city is identified by their IP. If you have trouble getting the country database inserted, try executing the scripts from console (windows command prompt or unix/linux shell): ./php install.php


Admin panel "Player Stats" category

Game server administrators flagged with ADMFLAG_ROOT can use the Administrators panel (sm_admin) to clean or clear player stats. Using this feature will physically remove data from the database, so be careful. There are multiple options to choose from. Here are the descriptions for the options:
Clear...
Clear stats from currently playing player... - Clear selected player stats. Selected from a list of players currently online at the same server.
Clear timed maps... - Clear map timings by gamemode. (confirmation required)
Clear Players - Delete all players from the database. (confirmation required)
Clear Maps - Set zero to all fields in maps table. This operation will not delete the rows in the database. (confirmation required)
Clear All - Does steps 2, 3 and 7. (confirmation required)
Remove Custom Maps - Deletes all maps where custom = 1. (confirmation required)
Clean Players - Deletes old players. Result is configurable with CVARs 42 and 43. (confirmation required)
Clear timed maps - Deletes all map timings. (confirmation required)

Console commands
sm_rank_clear - Game server administrators flagged with ADMFLAG_ROOT can clear the database like it was just installed. (confirmation required)
sm_rank_shuffle - Game server administrators flagged with ADMFLAG_KICK can shuffle teams by player PPM (Points Per Minute).
sm_rankmenu - Show a menu of all available commands.
sm_rankmute <0|1> - Mute or unmute Custom Player Stats.
sm_rank_motd <message> - Update Message Of The Day.

New CVARs
l4d_stats_ffire_cooldown (default = "10.0") Time in seconds for friendly fire cooldown
l4d_stats_ffire_cooldownmode (default = "1") Friendly fire cooldown mode. 0 = Disable, 1 = Player specific, 2 = General
l4d_stats_ledgegrap (default = "15") Base score for causing a survivor to grap a ledge
l4d_stats_infected_damage (default = "2") The amount of damage inflicted to Survivors to earn 1 point
l4d_stats_announceteam (default = "2") Chat announcment team messages to the team only mode. 0 = Print messages to all teams, 1 = Print messages to own team only, 2 = Print messages to own team and spectators only
l4d_stats_infected_win (default = "30") Base victory score for Infected Team
l4d_stats_medkitpenalty (default = "0.1") Score reduction for all Survivor earned points for each used Medkit (NormalPoints * (1 - MedkitsUsed * MedkitPenalty))
l4d_stats_medkitpenaltymax (default = "1.0") Maximum score reduction (the score reduction will not go over this value when a Medkit is used)
l4d_stats_medkitpenaltyfree (default = "0") Team Survivors can use this many Medkits for free without any reduction to the score
l4d_stats_survivor_death (default = "40") Base score for killing a Survivor
l4d_stats_survivor_incap (default = "15") Base score for incapacitating a Survivor
l4d_stats_perfectpouncedamage (default = "25") The amount of damage from Perfect Pounce to earn success points
l4d_stats_perfectpouncesuccess (default = "25") Base score for a successful Perfect Pounce
l4d_stats_nicepouncedamage (default = "15") The amount of damage from Nice Pounce to earn success points
l4d_stats_nicepouncesuccess (default = "10") Base score for a successful Nice Pounce
l4d_stats_hunterdamagecap (default = "25") Hunter stored damage cap
l4d_stats_boomersuccess (default = "5") Base score for a successfully vomiting on survivor
l4d_stats_boomerperfecthits (default = "4") The number of survivors that needs to get blinded to earn Boomer Perfect Vomit Award and success points
l4d_stats_boomerperfectsuccess (default = "30") Base score for a successful pounce
l4d_stats_tankdmgcap (default = "500") Maximum inflicted damage done by Tank to earn Infected damagepoints
l4d_stats_bulldozer (default = "200") Damage inflicted by Tank to earn Bulldozer Award and success points
l4d_stats_bulldozersuccess (default = "50") Base score for Bulldozer Award
l4d_stats_tankthrowrocksuccess (default = "5") Base score for a Tank thrown rock hit
l4d_stats_enablerealism (default = "1") [L4D2] Enable/Disable realism stat tracking
l4d_stats_realismmultiplier (default = "1.4") [L4D2] Realism score multiplier for coop score
l4d_stats_spitter (default = "5") [L4D2] Base score for killing a Spitter
l4d_stats_jockey (default = "5") [L4D2] Base score for killing a Jockey
l4d_stats_charger (default = "5") [L4D2] Base score for killing a Charger
l4d_stats_adrenaline (default = "15") [L4D2] Base score for giving Adrenaline to a friendly
l4d_stats_defib (default = "20") [L4D2] Base score for using a Defibrillator on a friendly
l4d_stats_jockeyride (default = "5") [L4D2] Base score for saving a friendly from a Jockey Ride
l4d_stats_chargerplummel (default = "5") [L4D2] Base score for saving a friendly from a Charger Plummel
l4d_stats_chargercarry (default = "5") [L4D2] Base score for saving a friendly from a Charger Carry
l4d_stats_caralarm (default = "50") [L4D2] Base score for a Triggering Car Alarm
l4d_stats_ffire_mode (default = "1") Friendly fire mode. 0 = Normal, 1 = Cooldown, 2 = Damage based
l4d_stats_ffire_multiplier (default = "1.5") Friendly fire damage multiplier (Formula: Score = Damage * Multiplier)
l4d_stats_announcerank (default = "1") Chat announcment for rank change
l4d_stats_announcerankinterval (default = "60") Rank change check interval
l4d_stats_matador (default = "30") [L4D2] Base score for killing a charging Charger with a melee weapon
l4d_stats_witchcrowned (default = "30") Base score for crowning a witch
l4d_stats_medkitbotmode (default = "1") Add score reduction when bot uses a medkit. 0 = No, 1 = Bot uses a Medkit to a human player, 2 = Bot uses a Medkit to other than itself, 3 = Yes
l4d_stats_adm_cleanoldplayers (default = "2") How many months old players (last online time) will be cleaned. 0 = Disabled
l4d_stats_adm_cleanplaytime (default = "30") How many minutes of playtime to not get cleaned from stats. 0 = Disabled
l4d_stats_enableteamversus (default = "1") [L4D2] Enable/Disable team versus stat tracking
l4d_stats_botscoremultiplier (default = "1.0") Multiplier to use when receiving bot related score penalty. 0 = Disable
l4d_stats_deployammoupgrade (default = "10") [L4D2] Base score for deploying ammo upgrade pack
l4d_stats_enablenegativescore (default = "1") Enable point losses (negative score)
l4d_stats_enablerankvote (default = "1") Enable voting of team shuffle by player PPM (Points Per Minute)
l4d_stats_enablescavenge (default = "1") [L4D2] Enable/Disable scavenge stat tracking
l4d_stats_enableteamscavenge (default = "1") [L4D2] Enable/Disable team scavenge stat tracking
l4d_stats_gascanpoured (default = "5") [L4D2] Base score for successfully pouring a gascan
l4d_stats_medicpointssv (default = "0") Survival medic points enabled
l4d_stats_rankvotetime (default = "20") Time to wait people to vote
l4d_stats_top10ppmplaytime (default = "30") Minimum playtime (minutes) to show in top10 ppm list
l4d_stats_soundsenabled (default = "1") Play sounds on certain events
l4d_stats_enablerealismvs (default = "1") [L4D2] Enable/Disable realism versus stat tracking
l4d_stats_realismvsmultiplier_s (default = "1.4") [L4D2] Realism score multiplier for survivors versus score
l4d_stats_realismvsmultiplier_i (default = "0.6") [L4D2] Realism score multiplier for infected versus score
l4d_stats_medkitpenaltyfree_r (default = "4") [L4D2] Team Survivors can use this many Medkits for free without any reduction to the score when playing in Realism gamemodes (-1 = use the value in l4d_stats_medkitpenaltyfree)
l4d_stats_chargerramsuccess (default = "40") [L4D2] Base score for a successful Charger Scattering Ram
l4d_stats_chargerramhits (default = "4") [L4D2] The number of impacts on survivors to earn Scattering Ram Award and success points
* l4d_stats_announceplayerjoined (default = "1") Announce joining player rank and points
* l4d_stats_announcemotd (default = "1") Announce the message of the day for the joining players
CVARs marked with asterisk (*) are new and with exclamation mark (!) are modified from previous major release.


The web stats have changed a bit. There are multiple new variables in CONFIG.PHP:
PHP Code:
$mysql_tableprefix = "";

// MySQL information for IP to Country DB
// Fill this if a separate database is used
$mysql_ip2c_server = "";
$mysql_ip2c_db = "";
$mysql_ip2c_user = "";
$mysql_ip2c_password = "";
$mysql_ip2c_tableprefix = "";

// Supported game versions
// 0 = Support both L4D1 and L4D2
// 1 = Left 4 Dead 1 (default)
// 2 = Left 4 Dead 2
$game_version = 1;

// Template for the stats page.
// Leave empty if the default template is used.
// Usage: "mytemplate" (requires directory ./templates/mytemplate existence)
$site_template = "";

$award_l4d2_file = "awards.l4d2.en.php";

// Refresh interval (seconds) for the front page (index.php)
// 0 = disabled
$stats_refreshinterval = 0;

// Game server address (adds a Steam connection link over the site name)
// Multiple game server addresses supported (just write multiple configurations and use the correct syntax for each of them)
/* THIS LINE: DO NOT MODIFY OR REMOVE */ $game_addresses = array();
// Syntax:
//   $game_addresses[] = array("<NAME>", "<ADDRESS>[:<PORT>]");
// Examples:
//   $game_addresses[] = array("Server 1: Left 4 Dead 2", "my.site.net:27016");
//   $game_addresses[] = array("Server 2: Kill Them Zombies", "123.0.0.234");

// Database time modifier (hours)
// 0 if the db time is the same as the websites
$dbtimemod = 0;

// Date format for player last online time
// http://www.php.net/manual/en/function.date.php
// Example: 24h - "M d, Y H:i";
$lastonlineformat = "M d, Y g:ia";

// Show player flags next to their names based on their IP
// 0 to disable
// Installation instructions:
//   1. Download and extract http://www.maxmind.com/download/geoip/database/GeoIPCountryCSV.zip to web stats root (same folder as install.php)
//   2. Execute install.php (use a web browser) - BE PATIENT AND WAIT FOR THE EXECUTION TO FINISH!
//   3. Delete files GeoIPCountryCSV.zip and GeoIPCountryWhois.csv when installation is successful
$showplayerflags = 0;

// Show player city name next to their flag and country name (player.php) based on their IP (has no effect when $showplayerflags = 0)
// 0 to disable
// Installation instructions:
//   1. Download latest GeoLiteCity_YYYYMMDD.zip from http://www.maxmind.com/app/geolitecity and extract the files to web stats root (same folder as install.php)
//   2. Execute install.php (use a web browser) - BE PATIENT AND WAIT FOR THE EXECUTION TO FINISH!
//   3. Delete files GeoLiteCity_YYYYMMDD.zip, GeoLiteCity-Blocks.csv and GeoLiteCity-Location.csv when installation is successful
$showplayercity = 0;

// Google Maps (player.php) additional URL parameters (URL postfix)
// Default: "&t=h&z=5"
//   Examples: (there is more!)
//     t => h = Satellite with labels / k = Satellite without labels / p = Terrain
//     z => Zoom factor
//     lci => com.panoramio.all = Photos / org.wikipedia.en = Wikipedia / com.youtube.all = Videos (combined with comma)
// Try out the usable parameters yourself
$googlemaps_addparam = "&t=h&z=5";

// Google Maps (index.php) API key (get yours from http://code.google.com/apis/maps/signup.html)
$googlemaps_apikey = "";

// Show Google Maps (index.php) location for the first # players online (useful when web stats hosts multiple game servers)
// 0 to show all players
$googlemaps_showplayersonlinecount = 0;

// Google Maps (index.php) players online additional URL parameters (URL postfix)
// Default: "&size=600x300&maptype=satellite&sensor=false"
$googlemaps_playersonline_addparam = "&size=600x300&maptype=satellite&sensor=false";

// Google Maps (index.php) zoom when only one players online (or only server is displayed)
$googlemaps_playersonline_zoom = 3;

// Show/hide link for the timed maps (also disables the page for parameterless use)
$timedmaps_show_all = False;

// Allow reading of player Steam profile (overrides all avatar related if set to False)
// Warning! Setting value to true can slow loading of some pages.
$steam_profile_read = True;

// Show/hide player avatars (overrides all other avatar related if set to False)
$players_avatars_show = True;

// Show/hide online player avatars
// Warning! Setting value to true will slow down the index page some, depending how
// many players are currently online.
$players_online_avatars_show = False;

// Number of players to show additional info at Top 10 -players list (set to 0 to disable)
// Shows player avatar and some other information.
// Warning! Setting a number higher than 0 (zero) will slow every page load a little.
$top10players_additional_info = 0;

// Show Message Of The Day in each page
$show_motd = True; 
You should set $game_version cariable correctly before running the install.php! They only affect on what maps will be inserted in the database and what values will be displayed in the web page. If you plan to mix the web stats with L4D and L4D2 servers, set the value to 0 (zero).


Also something noteworthy:
SPOKE TOO EARLY -> The strange "bug" that led to incorrect player names in the database should now be fixed. I have not seen any new bad player names in my DB. [FIX]
Web stats contain "hidden" statistics which you can find for example by placing the mouse over player points. (ToolTip)


[IMG]http://img51.**************/img51/2831/stats6.jpg[/IMG]


Quick installation guide

You can install this over the original Player Stats.
Prepare your MySQL database to accept connections from your web site and game server.
Download web stats (l4d_stats_web.zip) and extract it to your website. PHP support required! Alternatively, if you dont want or need the web stats, or if you don't have PHP or the skills to extract the queries from the install.php file, you can install the SQL dump (l4d2stats_sqldump.zip). You can skip to #7 if you decide to do the dump.
Rename config_example.php to config.php and edit it.
Execute install.php file.
Delete install.php file.
Add full read and write access to everyone for the website file /templates/awards_cache.html.
[OPTIONAL] Download l4d_stats.txt to /addons/sourcemod/gamedata. If you don't download this, your Rank Vote will be disabled.
Edit your databases.cfg file at /addons/sourcemod/config. Insert "l4dstats" entry with a valid connection info to your Custom Player Stats database.
Download compiled plugin (l4d_stats.smx) to /addons/sourcemod/plugins.

Tips
Bind a key to execute console command rankmenu. For example type bind f12 sm_rankmenu to your game console.

Credits
msleeper (the original author)
I got the pounce damage formula from someones plugin but can't find it anymore... Thanks for that and sorry I forgot who you were
kwski43 has been helping me out on the web stats. Thanks!
The Rank Vote functionality knowledge is ripped from some other plugin: Thanks AtomicStryker and Downtown1.
The signatures required by the Rank Vote were copied from some team swap plugin... I'll try to find it again. Sorry for forgetting it.

Very special thanks

I'd like to send my special thanks to Harm and Titan for the testing done when adding support to L4D2 and the help in overall they've given me. This would not have been possible to accomplish anywhere near this timeframe, if it wasn't for them. Planetsize thanks guys! 
19.01.2010 - Great work again! Thanks for helping me out.


Known issues
Scavenge was reported for giving team kill penalty on halftime? Can someone verify this?

ToDo
Fix the bugs.
[L4D2] Improve the new special infected stats collecting.
Implement client commands for getting list of top10 players from specific gamemodes.
Make it easier to do translations.
You tell me?

Related

You might want to check out for the current modifications and soon to be released stuff from MY TEST SITE. Currently I run two L4D servers at pilssi.dy.fi with ports 27015 and 27016.

This is how it all begun for me:
My first contact to msleeper and for the same time an attempt to help out...
The help was LOLed on by the author... 
My first real attempt to do something to help out...
Then after a while I started my own thread and programming extended gamemode support...
And when I got the first hack working, I started a New Plugin thread which for some reason broke down and had to be abandoned to get the plugin approved...
And now here you are reading this thread...  

History
19.10.2009 Web Stats / playerlist.php + awards.php
Bugfixes - They should now work better with the Versus statistics enabled.
19.11.2009 Plugin v1.2B87 ( Downloads = 95 )
Bugfixes - Huge scores from causing survivors falling damage.
14.12.2009 Support for L4D2 (also Realism) and also a bunch of new bugs (?) and fixed old ones. ( Downloads plugin = 164 / web stats = 158 )
15.12.2009 Plugin v1.3B12 ( Downloads = 36 )
Bugfixes - L4D2 awards fixed.
New features - A new way to calculate friendly fire point losses.
15.12.2009 Plugin v1.3B15 ( Downloads = 43 )
Bugfixes - A few new CVARs badly coded and the new friendly fire feature had flaws that were fixed. Sorry about spamming versions. 
16.12.2009 Web Stats / multiple scripts ( Downloads = 59 )
Bugfixes - Realism mode was not fully implemented to all scripts.
24.12.2009 Merry Christmas Release Plugin v1.3B36 and Web Stats ( Downloads plugin = 232 / web stats = 97 )
Bugfixes - High Level Securityfix to a few web stats pages. Please update your web stats! This bug is originated from msleeper scripts. ( Found by LART )
New features - Crown a witch award and Level a Charge award. Bot mode for medkit point reduction. Rank change announcement and "nextrank" command. Save a survivor from Charger and Jockey.
24.12.2009 Plugin v1.3B37 ( Downloads = 14 )
Bugfixes - Added some cleanup in the code. Very possible that it was not necessary, but if you already downloaded B36 and it gives you trouble: try this.
31.12.2009 Plugin v1.3B51 ( Downloads = 179 )
Bugfixes - Co-op round restart gave score loss twice.
New features - Nextrank panel was modified. New "Player Stats" category was added to Admin panel (sm_admin). New console command for server administrators "sm_rank_clear".
Noteworthy - Changed all CVAR names. Requested by approver.
31.12.2009 Web Stats / awards.en.php, awards.php, common.php and maps.php ( Downloads = 100 )
Bugfixes - Top 10 list not properly coded for Realism support. Hid custom maps that had total playtime = 0.
New features - Rank Awards page was added some new awards like witch crowning and L4D2 special infected related... stuff.
31.12.2009 Web Stats / awards.en.php, awards.php, config_example.php and new script awards.l4d2.en.php ( Downloads = 2 )
Bugfixes - Rank Awards page was not showing new stats properly. Sorry about spamming the versions again! You'll need to update your config.php.
1.1.2010 Plugin v1.3B52 ( Downloads = 35 )
New features - [L4D2] Support for Team Versus. Detect the Mod the plugin is ran and quit if not L4D or L4D2 ( SetFailState ).
Noteworthy - This version was posted as a response to this.
2.1.2010 Plugin v1.3B53 and Web Stats ( Downloads plugin = 32 / web stats = 36 )
Bugfixes - [L4D2] Friendly Fire modes, other than Damage Based, did not work at all.
New features - Web Stats Server Stats -page. ( Created by kwski43 - Thanks a lot! )
2.1.2010 Web Stats / layout.tpl and style.css ( Downloads = 17 )
Bugfixes - REPACK: Server Stats -link twice.
19.1.2010 Plugin v1.4B46 and Web Stats ( Downloads plugin = 420 / web stats = 216 )
General support for all gamemodes!
Bugfixes - Lots of them... don't remember any 
New features - New CVARs and modified l4d_stats_medkitpenaltyfree. New commands. More features to Admin Menu "Player Stats". New stats for Jockey and Survivors. Timed Maps. Removed Campaign "Chapters Completed" functionality (reason: Too unreliable) - Replaced it with Campaign Finale victory score and penalty for infected from the same event. Added score penalty for infected letting the survivors reach a saferoom.
Noteworthy - Unload plugin (SetFailState) if connecting to the DB fails (will hopefully lead to less problem solving with the server newbies).
28.1.2010 Plugin v1.4B61 and Web Stats ( Downloads plugin = 339 / web stats = 223 )
Bugfixes - top10ppm selections show correct player.
New features - Support for LAN. New commands. New CVAR (#54).
Noteworthy - If you are updating previous version of webstats, remember to update your config.php also!
2.2.2010 Plugin v1.4B64 and Web Stats ( Downloads plugin = 157 / web stats = 59 )
Bugfixes - rankvote displayed "DID NOT PASS" even though the team shuffle was executed in YES vote majority.
New features - Sound effects in certain events. New CVAR (#55). Web stats: Support templates ( kwski43 ). Web stats: More tooltips in player stats.
Noteworthy - The web stats file structure changed. Renamed some functions that may have caused problems with some other plugins. Changed the LAN support to work better.
4.2.2010 Plugin v1.4B66 and Web Stats ( Downloads plugin = 46 / web stats = 25 )
Bugfixes - Web stats rank awards page did not have player steamids in their links. Web stats player rank page displayed an error (PHP warning) if no players were found.
New features - Player IP logging and country flag display at the web stats.
Noteworthy - Database field added: Run updatetable.php.
7.2.2010 Web Stats / multiple scripts ( Downloads = 66 )
Bugfixes - PHP4 failed because scandir is new functionality in PHP5.
New features - Player city location and Google Maps integration.
Noteworthy - Loads of new configurables in config.php.
7.2.2010 Web Stats / index.php ( Downloads = 8 )
Bugfixes - Map zoom not set correctly when zero players on server.
12.2.2010 Web Stats / multiple scripts ( Downloads = 96 )
New features - Supports multiple game server steam linking (click to join).
Noteworthy - config.php variable site_address name changed.
15.2.2010 Web Stats / multiple scripts ( Downloads = 55 )
Bugfixes - Spitter avg damage not displayed correctly. With some rare cases the IP to Country may have returned invalid values (?).
New features - Refresh interval for the front page.
Noteworthy - Added one new configuration variable in config.php ($stats_refreshinterval).
30.4.2010 Plugin v1.4B76 and Web Stats ( Downloads plugin = 1441 / web stats = 800 )
General support for Realism Versus!
Bugfixes - Fix to Client not in game errors. No more error log spamming, I hope.
New features - Charger stats improved. Melee kills counted and stored. Realism gamemodes to have more configurables.
Noteworthy - Added new configuration variables in config.php. Table prefixes should work! IP2Country location data can be stored in to separate database!
1.5.2010 Web Stats / multiple scripts ( Downloads = 32 )
Bugfixes - IP2Country separated database was not working.
Noteworthy - Removed createtable.php and updatetable.php, and created install.php to cover them both.
2.5.2010 Plugin v1.4B80 ( Downloads = 76 )
HOTFIX release!
Bugfixes - Although the stats were probably all being properly collected, some major issues were left at the previous plugin release. Sorry about that!
7.5.2010 Plugin v1.4B86 and Web Stats ( Downloads plugin = 122 / web stats = 120 )
General support for all Mutations
Bugfixes - Scattering Ram award failed to store to DB because of a bug in query generation. Web stats was still missing some table prefix code and some of the scripts did not take count the new stored stats.
9.5.2010 Plugin v1.4B87 ( Downloads = 42 )
Bugfixes - Precached sounds may have caused problems with other plugins. Forgot to add mutations in one query. Thanks for the feedback Darkimmortal.
9.5.2010 Plugin v1.4B88 ( Downloads = 15 )
Bugfixes - Timedmaps query failed because of a typo in a query. Query string length in DisplayRank was too short.
10.5.2010 Plugin v1.4B89 ( Downloads = 43 )
Bugfixes - Still some typos in multiple places of the code. Damned! 
20.5.2010 Plugin v1.4B98 and Web Stats ( Downloads plugin = 200 / web stats = 196 )
Bugfixes - Infected players that caused damage to other infected players may have been counted as damage done to survivors. Not sure, but it shouldn't be possible anymore.
New features - Players settings! Currently there isn't anything else but the possibility to mute the Custom Player Stats. Unmute will enable normal plugin settings. New console commands sm_rankmute and sm_rankmutetoggle. New rankmenu selection: Settings.
Noteworthy - Database table added: Run install.php.
31.5.2010 Plugin v1.4B99 ( Downloads = 185 )
Bugfixes - Boomer Bile sometimes caused boomer blinding score for the survivor and once I even got a survivor kill award from the tank my team killed. Added some checks for certain routines.
31.5.2010 Plugin v1.4B100 ( Downloads = 9 )
Bugfixes - SQL_GetAffectedRows was called with a wrong parameter.
2.6.2010 Plugin v1.4B101 ( Downloads = 51 )
Bugfixes - Database clearing methods and particularily the maps table cleaning failed due to an error in the code.
Noteworthy - Uploaded a database SQL dump, which can be used as an alternative install method. Hopefully I will remember to do a new dump when changes occurs.
10.1.2011 Plugin v1.4B105 and Web Stats ( Downloads plugin = 1810 / web stats = 1265 )
Note - This release is just sumthn-sumthn... Sorry it took me so long to produce so little.
Bugfixes - Maybe? It took me so long for me to remember anything.
New features - A few more configurables to web stats config.php. Message Of The Day. Sounds effects to i.e. successful Boomer Perfect Blindness. Maybe something else?
Noteworthy - Database table added: Run install.php. I'll try to make some time to add new statistical features in the plugin. Read THIS POST to get a better view what was done to both web stats and the plugin.
17.1.2012 Web Stats ( Downloads = 1401 )
Annual update, starting with web stats...
Updated the install.php and other scripts to identify the missing default maps.
Added some additional PPM info on the campaign information pages.
1.2.2012 Plugin v1.4B116 ( Downloads = 2181 )
Bugfixes - Incorrect parameters when saving a survivor from a hunter lunge or a smoker pull (Thanks for pointing this out, Riviera). Was there something else - I don't remember?
New features - Send MOTD to every connecting player and to every player on the server when MOTD is changed. Show joining player rank: "Player muukis joined the game! (Rank: 123 / Points: 456)". New CVAR: l4d_stats_announceplayerjoined (default=1)
2.2.2012 Plugin v1.4B117 ( Downloads = 3 )
Bugfixes - Something went wrong on plugin upload. Downloading the compiled plugin failed due to an error in code, but I was able to compile the code manually (using the sourcemod online compiler).
New features - Type showmotd to chat to view the message of the day. New CVAR: l4d_stats_announcemotd (default=1)
1.8.2013 Plugin v1.4B121 ( Downloads = 2307 )
Bugfixes - Bot detection improved. Thanks for the feedback Hi-CAPA.
Noteworthy - Compile warnings cleaned. Uploaded new signatures for the Rank Vote team shuffle. Thanks for the feedback dcx2.
28.7.2015 SQL dump updated.
28.7.2015 Web Stats 2 uploaded.
Development upload from github. If you find anything annoying and/or tweaking, please let me know. It would be great if you could contribute to github too? Check the github link at the top of this post.
Please note that Web Stats 2 has an install wizard and you don't need to edit the config.php manually. Just open the site any page and the install wizard will open. Once you have completed the installer wizard your page is set up. If you install this to a separate folder you can run the Web Stats 2 in parallel to Web Stats (1).
18.1.2023 Plugin v1.5 ( Downloads = 8924 )
Updated to compile and run in SourceMod 1.11