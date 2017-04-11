#using scripts\shared\gameobjects_shared;
#using scripts\shared\math_shared;
#using scripts\shared\util_shared;
#using scripts\mp\gametypes\_globallogic;
#using scripts\mp\gametypes\_globallogic_audio;
#using scripts\mp\gametypes\_globallogic_score;
#using scripts\mp\gametypes\_globallogic_spawn;
#using scripts\mp\gametypes\_spawning;
#using scripts\mp\gametypes\_spawnlogic;
#using scripts\mp\killstreaks\_killstreaks;
#using scripts\mp\gametypes\_dogtags;
#using scripts\mp\_teamops;
#using scripts\mp\_util;
#using scripts\shared\array_shared;

#insert scripts\shared\shared.gsh;

/*
	TDM - Team Deathmatch
	Objective: 	Score points for your team by eliminating players on the opposing team
	Map ends:	When one team reaches the score limit, or time limit is reached
	Respawning:	No wait / Near teammates

	Level requirements
	------------------
		Spawnpoints:
			classname		mp_tdm_spawn
			All players spawn from these. The spawnpoint chosen is dependent on the current locations of teammates and enemies
			at the time of spawn. Players generally spawn behind their teammates relative to the direction of enemies.

		Spectator Spawnpoints:
			classname		mp_global_intermission
			Spectators spawn from these and intermission is viewed from these positions.
			Atleast one is required, any more and they are randomly chosen between.

	Level script requirements
	-------------------------
		Team Definitions:
			game["allies"] = "marines";
			game["axis"] = "nva";
			game["team3"] = "guys_who_hate_both_other_teams";
			This sets the nationalities of the teams. Allies can be american, british, or russian. Axis can be german.

		If using minefields or exploders:
			load::main();

	Optional level script settings
	------------------------------
		Soldier Type and Variation:
			game["soldiertypeset"] = "seals";
			This sets what character models are used for each nationality on a particular map.

			Valid settings:
				soldiertypeset	seals
*/

/*QUAKED mp_tdm_spawn (0.0 0.0 1.0) (-16 -16 0) (16 16 72)
Players spawn away from enemies and near their team at one of these positions.*/

/*QUAKED mp_tdm_spawn_axis_start (0.5 0.0 1.0) (-16 -16 0) (16 16 72)
Axis players spawn away from enemies and near their team at one of these positions at the start of a round.*/

/*QUAKED mp_tdm_spawn_allies_start (0.0 0.5 1.0) (-16 -16 0) (16 16 72)
Allied players spawn away from enemies and near their team at one of these positions at the start of a round.*/

/*QUAKED mp_tdm_spawn_team1_start (0.5 0.5 1.0) (-16 -16 0) (16 16 72)
Allied players spawn away from enemies and near their team at one of these positions at the start of a round.*/

/*QUAKED mp_tdm_spawn_team2_start (0.5 0.5 1.0) (-16 -16 0) (16 16 72)
Allied players spawn away from enemies and near their team at one of these positions at the start of a round.*/

/*QUAKED mp_tdm_spawn_team3_start (0.5 0.5 1.0) (-16 -16 0) (16 16 72)
Allied players spawn away from enemies and near their team at one of these positions at the start of a round.*/

/*QUAKED mp_tdm_spawn_team4_start (0.5 0.5 1.0) (-16 -16 0) (16 16 72)
Allied players spawn away from enemies and near their team at one of these positions at the start of a round.*/

/*QUAKED mp_tdm_spawn_team5_start (0.5 0.5 1.0) (-16 -16 0) (16 16 72)
Allied players spawn away from enemies and near their team at one of these positions at the start of a round.*/

/*QUAKED mp_tdm_spawn_team6_start (0.5 0.5 1.0) (-16 -16 0) (16 16 72)
Allied players spawn away from enemies and near their team at one of these positions at the start of a round.*/

#precache( "string", "OBJECTIVES_TDM" );
#precache( "string", "OBJECTIVES_TDM_SCORE" );
#precache( "string", "OBJECTIVES_TDM_HINT" );
#precache( "model", "p7_food_fruit_watermelon" );
#precache( "model", "p7_ammo_resupply_02_box" );
#precache( "fx", "fire/fx_bomberman" );

function main()
{
	globallogic::init();

	util::registerRoundSwitch( 0, 9 );
	util::registerTimeLimit( 0, 1440 );
	util::registerScoreLimit( 0, 50000 );
	util::registerRoundLimit( 0, 10 );
	util::registerRoundWinLimit( 0, 10 );
	util::registerNumLives( 0, 100 );
	
	globallogic::registerFriendlyFireDelay( level.gameType, 15, 0, 1440 );

	level.scoreRoundWinBased = ( GetGametypeSetting( "cumulativeRoundScores" ) == false );
	level.teamScorePerKill = GetGametypeSetting( "teamScorePerKill" );
	level.teamScorePerDeath = GetGametypeSetting( "teamScorePerDeath" );
	level.teamScorePerHeadshot = GetGametypeSetting( "teamScorePerHeadshot" );
	level.killstreaksGiveGameScore = GetGametypeSetting( "killstreaksGiveGameScore" );
	level.teamBased = true;
	level.overrideTeamScore = true;
	level.onStartGameType =&onStartGameType;
	level.onSpawnPlayer =&onSpawnPlayer;
	level.onRoundEndGame =&onRoundEndGame;
	level.onRoundSwitch =&onRoundSwitch;
	level.onPlayerKilled =&onPlayerKilled;

	gameobjects::register_allowed_gameobject( level.gameType );

	globallogic_audio::set_leader_gametype_dialog ( "startTeamDeathmatch", "hcStartTeamDeathmatch", "gameBoost", "gameBoost" );
	
	// Sets the scoreboard columns and determines with data is sent across the network
	globallogic::setvisiblescoreboardcolumns( "score", "kills", "deaths", "kdratio", "assists" ); 
}

function onStartGameType()
{
	setClientNameMode("auto_change");

	if ( !isdefined( game["switchedsides"] ) )
		game["switchedsides"] = false;

	if ( game["switchedsides"] )
	{
		oldAttackers = game["attackers"];
		oldDefenders = game["defenders"];
		game["attackers"] = oldDefenders;
		game["defenders"] = oldAttackers;
	}
	
	level.displayRoundEndText = false;
	
	// now that the game objects have been deleted place the influencers
	spawning::create_map_placed_influencers();
	
	level.spawnMins = ( 0, 0, 0 );
	level.spawnMaxs = ( 0, 0, 0 );

	foreach( team in level.teams )
	{
		util::setObjectiveText( team, &"OBJECTIVES_TDM" );
		util::setObjectiveHintText( team, &"OBJECTIVES_TDM_HINT" );
	
		if ( level.splitscreen )
		{
			util::setObjectiveScoreText( team, &"OBJECTIVES_TDM" );
		}
		else
		{
			util::setObjectiveScoreText( team, &"OBJECTIVES_TDM_SCORE" );
		}
		
		spawnlogic::add_spawn_points( team, "mp_tdm_spawn" );

		
		spawnlogic::place_spawn_points( spawning::getTDMStartSpawnName(team) );
	}
		
	spawning::updateAllSpawnPoints();
	
	level.spawn_start = [];
	
	foreach( team in level.teams )
	{
		level.spawn_start[ team ] =  spawnlogic::get_spawnpoint_array( spawning::getTDMStartSpawnName(team) );
	}

	level.mapCenter = math::find_box_center( level.spawnMins, level.spawnMaxs );
	setMapCenter( level.mapCenter );

	spawnpoint = spawnlogic::get_random_intermission_point();
	setDemoIntermissionPoint( spawnpoint.origin, spawnpoint.angles );
	
	
	
	//removed action loop -CDC
	level thread onScoreCloseMusic();

	if ( !util::isOneRound() )
	{
		level.displayRoundEndText = true;
		if( level.scoreRoundWinBased )
		{
			globallogic_score::resetTeamScores();
		}
	}
	
	if( IS_TRUE( level.droppedTagRespawn ) )
		level.numLives = 1;

	grid();
}

function onSpawnPlayer(predictedSpawn)
{
	self.usingObj = undefined;
	
	if ( level.useStartSpawns && !level.inGracePeriod && !level.playerQueuedRespawn )
	{
		level.useStartSpawns = false;
	}

	self.moveSpeed = 0.8;
	self.bombCount = 0;
	self.explosionLength = 1;
	self.maxBombCount = 2;
	self.invulnerable = false;
	self.hasPowerBomb = false;
	self thread camera();
	self thread playerUseBombs();

	spawning::onSpawnPlayer(predictedSpawn);
}

function onEndGame( winningTeam )
{
	if ( isdefined( winningTeam ) && isdefined( level.teams[winningTeam] ) )
		globallogic_score::giveTeamScoreForObjective( winningTeam, 1 );
}

function onRoundSwitch()
{
	game["switchedsides"] = !game["switchedsides"];

	if ( level.scoreRoundWinBased ) 
	{
		foreach( team in level.teams )
		{
			[[level._setTeamScore]]( team, game["roundswon"][team] );
		}
	}
}

function onRoundEndGame( roundWinner )
{
	if ( level.scoreRoundWinBased ) 
	{
		foreach( team in level.teams )
		{
			[[level._setTeamScore]]( team, game["roundswon"][team] );
		}
	}
	
	return [[level.determineWinner]]();
}

function onScoreCloseMusic()
{
	teamScores = [];
	
  while( !level.gameEnded )
  {
    scoreLimit = level.scoreLimit;
    scoreThreshold = scoreLimit * .1;
    scoreThresholdStart = abs(scoreLimit - scoreThreshold);
    scoreLimitCheck = scoreLimit - 10;

		topScore = 0;
		runnerUpScore = 0;
  	foreach( team in level.teams )
  	{
	    score = [[level._getTeamScore]]( team );
	    
	    if ( score > topScore )
	    {
	    	runnerUpScore = topScore;
	    	topScore = score;
	    }
	    else if ( score > runnerUpScore )
	    {
	    	runnerUpScore = score;
	    }
	  }
 
    scoreDif = (topScore - runnerUpScore);
            
	if( topScore >= scoreLimit*.5)
	{
		level notify( "sndMusicHalfway" );
		return;
	}
      
    wait(1);
  }
}

function onPlayerKilled( eInflictor, attacker, iDamage, sMeansOfDeath, weapon, vDir, sHitLoc, psOffsetTime, deathAnimDuration )
{
	if( IS_TRUE( level.droppedTagRespawn ) )
	{
		thread dogtags::checkAllowSpectating();

		should_spawn_tags = self dogtags::should_spawn_tags(eInflictor, attacker, iDamage, sMeansOfDeath, weapon, vDir, sHitLoc, psOffsetTime, deathAnimDuration);
		
		// we should spawn tags if one the previous statements were true and we may not spawn
		should_spawn_tags = should_spawn_tags && !globallogic_spawn::maySpawn();
		
		if( should_spawn_tags )
			level thread dogtags::spawn_dog_tag( self, attacker, &dogtags::onUseDogTag, false );
	}
	
	if ( isPlayer( attacker ) == false || attacker.team == self.team )
		return;	
	
	if( !isdefined( killstreaks::get_killstreak_for_weapon( weapon ) ) || IS_TRUE( level.killstreaksGiveGameScore ) )				
	{
		attacker globallogic_score::giveTeamScoreForObjective( attacker.team, level.teamScorePerKill );
		self globallogic_score::giveTeamScoreForObjective( self.team, level.teamScorePerDeath * -1 );
		if ( sMeansOfDeath == "MOD_HEAD_SHOT" )
		{
			attacker globallogic_score::giveTeamScoreForObjective( attacker.team, level.teamScorePerHeadshot );
		}
	}
}

function playerUseBombs()
{
	for(;;)
	{
		if( self UseButtonPressed() )
		{
			self thread spawnBomb();
			wait .2;
		}

		WAIT_SERVER_FRAME;
	}
}

function grid() // Initialisation
{
	if( !isDefined( level.mapWidth ) ) 
		level.mapWidth = 13;

	if( !isDefined( level.mapLength ) )
		level.mapLength = 13;

	totalUnits = level.mapWidth * level.mapLength;

	level.grid = [];
	level.powerUps = [];
	level.crates = GetEntArray( "wood", "targetname" );

	for( i = 0; i < totalUnits; i++ )
	{
		level.grid[ i ] = getEnt( "grid_" + i, "targetname" );
		level.grid[ i ].type = 0;
		level.grid[ i ].containsBomb = false;
		level.grid[ i ].powerBomb = false;
	}

	baseCoords = [];

	baseCoords[ baseCoords.size ] = 14;
	baseCoords[ baseCoords.size ] = 16;
	baseCoords[ baseCoords.size ] = 18;
	baseCoords[ baseCoords.size ] = 20;
	baseCoords[ baseCoords.size ] = 22;
	baseCoords[ baseCoords.size ] = 24;

	level.powerUps[ level.powerUps.size ] = "IncreaseLength";
	level.powerUps[ level.powerUps.size ] = "IncreaseSpeed";
	level.powerUps[ level.powerUps.size ] = "KickBomb";
	level.powerUps[ level.powerUps.size ] = "PowerBomb";
	level.powerUps[ level.powerUps.size ] = "Invulnerable";
	level.powerUps[ level.powerUps.size ] = "IncreasedBombCount";	

	// Need to clean this up so it matchec level.mapWidth, should anyone want to make a bomberman map
	for( i = 0; i < baseCoords.size; i++ )
		for( j = 0; j < 6; j++ )
			level.grid[ baseCoords[ i ] + ( 26 * j ) ].type = 1;
}

function spawnBomb()
{
	position = getPosition( self );

	if( level.grid[ position ].containsBomb || self.bombCount == getMaxBombCount() )
		return;

	self.bombCount++;
	level.grid[ position ].containsBomb = true;

	if( self.hasPowerBomb )
	{
		level.grid[ position ].powerBomb = true;
		self.hasPowerBomb = false;
	}

	// Melon
	level.grid[ position ].melon = spawn( "script_model", level.grid[ position ].origin );
	level.grid[ position ].melon setModel( "p7_food_fruit_watermelon" );
	level.grid[ position ].melon SetPlayerCollision( false );

	// Need to change to monkey bomb and edit anim
	for( i = 0; i <= 3; i += .06 )
	{
		if( !isDefined( level.grid[ position ].melon ) )
		{
			self.bombCount--;
			break; 
		}

		if( getPosition( self ) != position ) level.grid[ position ].melon SetPlayerCollision( true );

		level.grid[ position ].melon SetScale( ( i + .06 ) + 2 );
		wait .06;
	}

	WAIT_SERVER_FRAME;

	// This only occurs if the melon still exists - Part of logic for chaining
	if( isDefined( level.grid[ position ].melon ) ) 
	{
		level.allLocations = [];
		getAllLocations( position );
		level.AllLocations = removeDuplicate( level.AllLocations );

		explode();

		self.bombCount--;

		wait 2;
	}
	else
		wait 2;
}

function checkBombsWithinRange( array ) // Check for chaining and check for players inside
{
	locations = [];

	foreach( loc in array )
		if( level.grid[ loc ].containsBomb )
			locations[ locations.size ] = loc;

	return locations;
}

function containsBox( position )
{
	for( i = 0; i < level.crates.size; i++ )
		if( level.crates[ i ].origin == level.grid[ position ].origin )
			return true;

	return false;
}

function getPosition( player )
{
	position = undefined;

	for( i = 0; i < level.grid.size; i++ )
		if( player IsTouching( level.grid[ i ] ) )
			position = i;

	return position;
}

function getAllLocations( position )
{
	hitLocations = getHitLocations( position );
	bombs = checkBombsWithinRange( hitLocations );

	for( i = 0; i < hitLocations.size; i++ ) level.allLocations[ level.allLocations.size ] = hitLocations[ i ];

	newBombs = [];

	for( i = 0; i < bombs.size; i++ )
	{
		if( position == bombs[ i ] ) continue;
		newBombs[ newBombs.size ] = bombs[ i ];
	}

	level.grid[ position ].melon Delete();
	level.grid[ position ].melon = undefined;
	level.grid[ position ].containsBomb = false;
	level.grid[ position ].powerBomb = false;

	for( i = 0; i < newBombs.size; i++ ) thread getAllLocations( newBombs[ i ] );
}

function getHitLocations( position )
{
	bombPlacedHitLocations = [];

	bombPlacedHitLocations = filter( "NORTH", bombPlacedHitLocations, position );
	bombPlacedHitLocations = filter( "EAST", bombPLacedHitLocations, position );
	bombPlacedHitLocations = filter( "SOUTH", bombPLacedHitLocations, position );
	bombPlacedHitLocations = filter( "WEST", bombPLacedHitLocations, position );
	bombPlacedHitLocations[ bombPlacedHitLocations.size ] = position;

	return bombPlacedHitLocations;
}

function filter( dir, array, position )
{
	switch( dir )
	{
		case "NORTH":
			if( level.grid[ position ].powerBomb )
			{
				for( i = 1; position + ( -level.mapLength * i ) >= 0; i++ ) array[ array.size ] = position + ( -level.mapWidth * i );
				break;
			}

			for( i = 1; i <= self.explosionLength; i++ )
			{
				if( level.grid[ position + ( -level.mapWidth * i ) ].type ) break;
				if( position + ( -level.mapWidth * i ) < 0 ) break;
				if( containsBox( position + ( - level.mapWidth * i ) ) )
				{
					array[ array.size ] = position + ( -level.mapWidth * i );
					break;
				}
				else 
					array[ array.size ] = position + ( -level.mapWidth * i );
			}
			break;

		case "EAST":
			if( level.grid[ position ].powerBomb )
			{	
				modulo = position % level.mapWidth;
				amount = level.mapWidth - modulo;

				for( i = 1; i < amount; i++ ) array[ array.size ] = position + ( 1 * i );
				break;
			}

			for( i = 1; i <= self.explosionLength; i++ )
			{
				if( level.grid[ position + ( 1 * i ) ].type ) break;
				if( position + ( 1 * i ) % level.mapWidth == 0 ) break;
				if( containsBox( position + ( 1 * i ) ) )
				{
					array[ array.size ] = position + ( 1 * i );
					break;
				}
				else 
					array[ array.size ] = position + ( 1 * i );
			}
			break;

		case "SOUTH":
			if( level.grid[ position ].powerBomb )
			{
				for( i = 1; position + ( level.mapLength * i ) <= ( level.mapWidth * level.mapLength ) - 1; i++ ) array[ array.size ] = position + ( level.mapWidth * i );
				break;
			}

			for( i = 1; i <= self.explosionLength; i++ )
			{
				if( level.grid[ position + ( level.mapWidth * i ) ].type ) break;
				if( position + ( level.mapWidth * i ) > ( level.mapWidth * level.mapLength ) - 1 ) break;
				if( containsBox( position + ( level.mapWidth * i ) ) )
				{
					array[ array.size ] = position + ( level.mapWidth * i );
					break;
				}
				else 
					array[ array.size ] = position + ( level.mapWidth * i );
			}
			break;

		case "WEST":
			if( level.grid[ position ].powerBomb )
			{	
				modulo = position % level.mapWidth;

				for( i = 1; i <= modulo; i++ ) array[ array.size ] = position + ( -1 * i );
				break;
			}

			for( i = 1; i <= self.explosionLength; i++ )
			{
				if( !position || position + ( -1 * i ) < 0 ) break;
				if( level.grid[ position + ( -1 * i ) ].type ) break;
				if( position + ( -1 * i ) % level.mapWidth == level.mapWidth - 1 ) break;
				if( containsBox( position + ( -1 * i ) ) )
				{
					array[ array.size ] = position + ( -1 * i );
					break;
				}
				else 
					array[ array.size ] = position + ( -1 * i );
			}
			break;
	}

	return array;
}

function removeDuplicate( array )
{
	array = array::sort_by_value( array, true );
	arrayFixed = [];

	for( i = 0; i < array.size; i++ )
	{
		if( array[ i ] == array[ i + 1 ] ) continue;
		arrayFixed[ arrayFixed.size ] = array[ i ];
	}

	return arrayFixed;
}

function explode()
{
	explosions = [];
	fx = [];

	for( i = 0; i < level.allLocations.size; i++ )
	{
		fx[ fx.size ] = SpawnFX( "fire/fx_bomberman", level.grid[ level.allLocations[ i ] ].origin );
		fx[ fx.size - 1 ].angles = level.grid[ level.allLocations[ i ] ].angles;
		TriggerFX( fx[ fx.size - 1 ] );
	}

	for( i = 0; i < level.allLocations.size; i++ )
		for( j = 0; j < level.crates.size; j++ )
			if( level.crates[ j ].origin == level.grid[ level.allLocations[ i ] ].origin )
			{
				level.crates[ j ] Delete();
				if( RandomInt( 6 ) == 5 ) thread spawnPowerup( level.allLocations[ i ], level.powerUps[ RandomInt( level.powerUps.size ) ] );
			}

	for( i = 0; i <= 1.5; i += 0.1 )
	{
		foreach( player in level.players )
			for( j = 0; j < level.allLocations.size; j++ )
				if( player IsTouching( level.grid[ level.allLocations[ j ] ] ) && player.invulnerable == false )
					player kill();
		wait 0.1;
	}

	for( i = 0; i < fx.size; i++ )
		fx[ i ] Destroy();
}

function spawnPowerup( position, name )
{
	model = spawn( "script_model", level.grid[ position ].origin );
	model SetModel( "p7_ammo_resupply_02_box" );

	while( isDefined( model ) )
	{
		foreach( player in level.players )
			if( player isTouching( level.grid[ position ] ) )
			{
				pu_player = player;
				model Delete();
			}

		WAIT_SERVER_FRAME;
	}

	switch( name )
	{
		case "IncreaseLength":     pu_player increaseLength();    break;
		case "IncreaseSpeed":      pu_player increaseSpeed();     break;
		case "KickBomb":           pu_player kickBomb();          break;
		case "PowerBomb":          pu_player powerBomb();         break;
		case "Invulnerable":       pu_player invulnerable();      break;
		case "IncreasedBombCount": pu_player increaseBombCount(); break;
	}
}

function setExplosionLength( length ) { self.explosionLength = length; }
function getExplosionLength() { return self.explosionLength; }
function setMaxBombCount( length ) { self.maxBombCount = length; }
function getMaxBombCount() { return self.maxBombCount; }

function increaseLength() { setExplosionLength( getExplosionLength() + 1 ); self IPrintLn( "Explosion length: " + getExplosionLength() ); }
function increaseSpeed() { self SetMoveSpeedScale( self GetMoveSpeedScale() + 0.2 ); self iPrintLn( "Movespeed: " + self GetMoveSpeedScale() ); }
function increaseBombCount() { setMaxBombCount( getMaxBombCount() + 1 ); self IPrintLn( "Max bomb count placed: " + getMaxBombCount() ); }
function powerBomb() { self.hasPowerBomb = true; self iPrintLn( "Next bomb will be a power bomb" ); }

function kickBomb()
{
	self IPrintLn( "kick bomb [WIP]" );
}

function invulnerable()
{
	self IPrintLn( "Invulnerable for 10 seconds" );
	for( i = 0; i <= 10; i += 0.1 )
	{
		if( !self.invulnerable )
			self.invulnerable = true;

		wait 0.1;
	}
}

function camera()
{
	wait .1;
	self setClientUIVisibilityFlag( "hud_visible", 0 );
	self allowADS( false );
	self AllowJump( false );
	self AllowDoubleJump( false );
	self SetMoveSpeedScale( 0.8 );
	self TakeAllWeapons();
	self DisableWeaponFire();

	camera = spawn( "script_model", self.origin + ( 0, 0, 350 ) );
	camera.angles = ( 90, 90, 0 );
	camera setModel( "tag_origin" );

	self CameraSetLookAt( camera );
	self CameraSetPosition( camera );
	self CameraActivate( true );

	while(1)
	{
		camera.origin = self.origin + ( 0, 0, 350 );
		self SetPlayerAngles( ( 0, 0, 0 ) );
		wait 0.001;
	}
}