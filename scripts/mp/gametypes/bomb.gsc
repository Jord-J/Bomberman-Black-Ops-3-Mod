#using scripts\codescripts\struct;

#using scripts\shared\callbacks_shared;
#using scripts\shared\rank_shared;
#using scripts\shared\system_shared;

#insert scripts\shared\shared.gsh;

#using scripts\mp\_util;

#using scripts\shared\gameobjects_shared;
#using scripts\shared\clientfield_shared;
#using scripts\shared\music_shared;
#using scripts\shared\math_shared;
#using scripts\shared\util_shared;
#using scripts\shared\array_shared;
#using scripts\shared\hud_util_shared;
#using scripts\shared\hud_message_shared;
#using scripts\mp\gametypes\_globallogic;
#using scripts\mp\gametypes\_globallogic_player;
#using scripts\mp\gametypes\_globallogic_ui;
#using scripts\mp\gametypes\_globallogic_audio;
#using scripts\mp\gametypes\_globallogic_utils;
#using scripts\mp\gametypes\_spawning;
#using scripts\mp\gametypes\_spawnlogic;
#using scripts\mp\_behavior_tracker;
#using scripts\mp\_util;

function main()
{
	globallogic::init();

	util::registerTimeLimit( 0, 10 );
	util::registerRoundLimit( 0, 10 );
	util::registerScoreLimit( 0, 10000 );
	util::registerNumLives( 0, 100 );

	level.onStartGameType = &onStartGameType;
	level.onSpawnPlayer =&onSpawnPlayer;
	level.onTimeLimit =&onTimeLimit;

    globallogic::setvisiblescoreboardcolumns( "score" ); 
}

function onStartGameType()
{
	SetClientNameMode( "auto_change" );
	
	level.spawnMins = ( 0, 0, 0 );
	level.spawnMaxs = ( 0, 0, 0 );

	spawnlogic::place_spawn_points( "mp_dm_spawn_start" );
	level.spawn_start = spawnlogic::get_spawnpoint_array( "mp_dm_spawn_start" );

	spawning::updateAllSpawnPoints();

	level.useStartSpawns = true;
    level.alwaysUseStartSpawns = true;

	spawnpoint = spawnlogic::get_random_intermission_point();
	setDemoIntermissionPoint( spawnpoint.origin, spawnpoint.angles );
	
	level.displayRoundEndText = false;
	level.doTopScorers = false;
	level.doEndgameScoreboard = false;

	grid();
}

function onSpawnPlayer(predictedSpawn)
{
	spawning::onSpawnPlayer( predictedSpawn );

	self.moveSpeed = 0.8;
	self.bombCount = 0;
	self.explosionLength = 1;
	self.maxBombCount = 2;
	self.invulnerable = false;
	self.hasPowerBomb = false;

	self thread camera();
	self thread hudDisplayStats();
	self thread playerUseBombs();
}

function onTimeLimit() { endGame( undefined, undefined ); }

function camera()
{
	WAIT_SERVER_FRAME; // Have to add a ltitle delay
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
		WAIT_SERVER_FRAME;
	}
}

function playerUseBombs()
{
	for(;;)
	{
		if( self UseButtonPressed() )
		{
			self thread spawnBomb();
			WAIT_SERVER_FRAME;
		}

		WAIT_SERVER_FRAME;
	}
}

// |--------------------------------------------------------------
// | Grid initialisation - Call this on the end of start gametype
// |--------------------------------------------------------------
// |
// | Do appropiate checks to see if the current map is compatible
// | for this Mod. Although i'm releasing an offical map for the Mod,
// | it is still possible for others to make maps for the Mod.

function grid()
{
	level.mapWidth = 13;
	level.mapLength = 13;

	totalUnits = level.mapWidth * level.mapLength;

	level.grid = [];
	level.powerUps = [];
	level.crates = GetEntArray( "wood", "targetname" );

	for( i = 0; i < totalUnits; i++ )
	{
		level.grid[ i ] = getEnt( "grid_" + i, "targetname" );
		level.grid[ i ].isBlock = false;
		level.grid[ i ].containsBomb = false;
		level.grid[ i ].powerBomb = false;
	}

	// Need to redo the logic for baseCoords
	baseCoords = [];

	baseCoords[ baseCoords.size ] = 14;
	baseCoords[ baseCoords.size ] = 16;
	baseCoords[ baseCoords.size ] = 18;
	baseCoords[ baseCoords.size ] = 20;
	baseCoords[ baseCoords.size ] = 22;
	baseCoords[ baseCoords.size ] = 24;

	level.powerUps[ level.powerUps.size ] = "IncreaseLength";
	level.powerUps[ level.powerUps.size ] = "IncreaseSpeed";
	level.powerUps[ level.powerUps.size ] = "PowerBomb";
	level.powerUps[ level.powerUps.size ] = "Invulnerable";
	level.powerUps[ level.powerUps.size ] = "IncreasedBombCount";	

	for( i = 0; i < baseCoords.size; i++ )
		for( j = 0; j < ( level.mapWidth / 2 ) - 1; j++ )
			level.grid[ baseCoords[ i ] + ( ( level.mapWidth * 2 ) * j ) ].isBlock = true;
}

// |------------------------------------------------------------
// | Bomb logic function - Call this function on a player
// |------------------------------------------------------------
// |
// | 1. Check to see if there's a bomb already placed and check if reached players maximum bomb count,
// |    if the condition(s) are met, do appropiate action.
// | 2. Check to see if the bomb placed is a powerbomb, if the condition is met, do appropiate action.
// | 3. Spawn bomb models, setPlayerCollision to false so player doesn't get trapped. Do a for loop to
// |    check if the bomb still defined or player has exited the bomb position. If the condition(s) are
// | 	met, do appropiate action. (Bomb may not exist as it may be in a bomb chain)
// | 4. If the bomb is still defined, check to see if other bombs are within range, if so apply this
// |	check to every bomb that is in range of each other. Store all hit locations into an array. EXPLODE!!!

function spawnBomb()
{
	position = GetPosition( self );

	// Don't need to check if level.grid[ position ] is defined as the if provides that check
	if( level.grid[ position ].containsBomb || self.bombCount == getMaxBombCount() )
		return;

	level.grid[ position ].containsBomb = true;
	self.bombCount++;

	if( self.hasPowerBomb )
	{
		level.grid[ position ].powerBomb = true;
		self.hasPowerBomb = false; // This is if the player places another bomb before power bomb has exploded
	}

	// Bomb model
	level.grid[ position ].bomb = Spawn( "script_model", level.grid[ position ].origin - ( 0, 0, 30 ) );
	level.grid[ position ].bomb SetModel( "bobomb" );
	level.grid[ position ].bomb SetPlayerCollision( false );

	level.grid[ position ].handle = Spawn( "script_model", level.grid[ position ].origin - ( 0, 0, 12 ) );
	level.grid[ position ].handle SetModel( "bobomb_handle" );

	// I used .2 as anything less seemed jaggy when leaving bomb position
	for( i = 0; i <= 3; i += .2 )
	{
		if( !isdefined( level.grid[ position ].bomb ) )
		{
			self.bombCount--;
			break;
		}

		if( GetPosition( self ) != position ) level.grid[ position ].bomb SetPlayerCollision( true );

		level.grid[ position ].handle RotateRoll( 50, .2 );
		wait .2;
	}

	WAIT_SERVER_FRAME;

	// This only occurs if the bomb still exists - Part of logic for chaining
	if( isdefined( level.grid[ position ].bomb ) ) 
	{
		level.allLocations = [];
		GetAllLocations( position );
		level.AllLocations = RemoveDuplicate( level.AllLocations );

		self.bombCount--;

		explode();
	}
}

function GetPosition( player )
{
	for( i = 0; i < level.grid.size; i++ )
		if( player IsTouching( level.grid[ i ] ) )
			position = i;

	return position;
}

function GetAllLocations( position )
{
	hitLocations = GetHitLocations( position );
	bombs = CheckBombsWithinRange( hitLocations );

	for( i = 0; i < hitLocations.size; i++ ) level.allLocations[ level.allLocations.size ] = hitLocations[ i ];

	newBombs = [];

	for( i = 0; i < bombs.size; i++ )
	{
		if( position == bombs[ i ] ) continue;
		newBombs[ newBombs.size ] = bombs[ i ];
	}

	level.grid[ position ].bomb Delete();
	level.grid[ position ].handle Delete();
	level.grid[ position ].bomb = undefined;
	level.grid[ position ].handle = undefined;
	level.grid[ position ].containsBomb = false;
	level.grid[ position ].powerBomb = false;

	for( i = 0; i < newBombs.size; i++ ) thread GetAllLocations( newBombs[ i ] );
}

function GetHitLocations( position )
{
	bombPlacedHitLocations = [];

	bombPlacedHitLocations = Filter( "NORTH", bombPlacedHitLocations, position );
	bombPlacedHitLocations = Filter( "EAST", bombPLacedHitLocations, position );
	bombPlacedHitLocations = Filter( "SOUTH", bombPLacedHitLocations, position );
	bombPlacedHitLocations = Filter( "WEST", bombPLacedHitLocations, position );
	bombPlacedHitLocations[ bombPlacedHitLocations.size ] = position;

	return bombPlacedHitLocations;
}

function Filter( direction, array, position )
{
	switch( direction )
	{
		case "NORTH":
			if( level.grid[ position ].powerBomb )
			{
				for( i = 1; position + ( -level.mapLength * i ) >= 0; i++ )
				{ 
					if( level.grid[ position + ( -level.mapLength * i ) ].isBlock ) break;
					array[ array.size ] = position + ( -level.mapWidth * i );
				}
				break;
			}

			for( i = 1; i <= self.explosionLength; i++ )
			{
				if( level.grid[ position + ( -level.mapWidth * i ) ].isBlock ) break;
				if( position + ( -level.mapWidth * i ) < 0 ) break;
				if( ContainsBox( position + ( - level.mapWidth * i ) ) )
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

				for( i = 1; i < amount; i++ ) 
				{	
					if( level.grid[ position + ( 1 * i ) ].isBlock ) break;
					array[ array.size ] = position + ( 1 * i );
				}
				break;
			}

			for( i = 1; i <= self.explosionLength; i++ )
			{
				if( level.grid[ position + ( 1 * i ) ].isBlock ) break;
				if( position + ( 1 * i ) % level.mapWidth == 0 ) break;
				if( ContainsBox( position + ( 1 * i ) ) )
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
				for( i = 1; position + ( level.mapLength * i ) <= ( level.mapWidth * level.mapLength ) - 1; i++ )
				{
					if( level.grid[ position + ( level.mapLength * i ) ].isBlock ) break;
					array[ array.size ] = position + ( level.mapWidth * i );
				}
				break;
			}

			for( i = 1; i <= self.explosionLength; i++ )
			{
				if( level.grid[ position + ( level.mapWidth * i ) ].isBlock ) break;
				if( position + ( level.mapWidth * i ) > ( level.mapWidth * level.mapLength ) - 1 ) break;
				if( ContainsBox( position + ( level.mapWidth * i ) ) )
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

				for( i = 1; i <= modulo; i++ )
				{
					if( level.grid[ position + ( -1 * i ) ].isBlock ) break;
					array[ array.size ] = position + ( -1 * i );
				}
				break;
			}

			for( i = 1; i <= self.explosionLength; i++ )
			{
				if( !position || position + ( -1 * i ) < 0 ) break;
				if( level.grid[ position + ( -1 * i ) ].isBlock ) break;
				if( position + ( -1 * i ) % level.mapWidth == level.mapWidth - 1 ) break;
				if( ContainsBox( position + ( -1 * i ) ) )
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

function ContainsBox( position )
{
	for( i = 0; i < level.crates.size; i++ )
		if( level.crates[ i ].origin == level.grid[ position ].origin )
			return true;

	return false;
}

function CheckBombsWithinRange( array ) // Check for chaining and check for players inside
{
	locations = [];

	foreach( loc in array )
		if( level.grid[ loc ].containsBomb )
			locations[ locations.size ] = loc;

	return locations;
}

function RemoveDuplicate( array )
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
	FX = [];

	for( i = 0; i < level.allLocations.size; i++ )
	{
		FX[ FX.size ] = SpawnFX( "fire/fx_bomberman", level.grid[ level.allLocations[ i ] ].origin );
		TriggerFX( FX[ FX.size - 1 ] );
	}

	for( i = 0; i < level.allLocations.size; i++ )
		for( j = 0; j < level.crates.size; j++ )
			if( level.crates[ j ].origin == level.grid[ level.allLocations[ i ] ].origin )
			{
				level.crates[ j ] Delete();
				if( RandomInt( 6 ) == 5 ) thread SpawnPowerup( level.allLocations[ i ], level.powerUps[ RandomInt( level.powerUps.size ) ] );
			}

	for( i = 0; i <= 1.5; i += 0.1 )
	{
		foreach( player in level.players )
			for( j = 0; j < level.allLocations.size; j++ )
				if( player IsTouching( level.grid[ level.allLocations[ j ] ] ) && !player.invulnerable )
					player Kill();

		wait 0.1;
	}

	for( i = 0; i < FX.size; i++ ) FX[ i ] Delete();
}

function SpawnPowerup( position, name )
{
	model = spawn( "script_model", level.grid[ position ].origin );
	model SetModel( "powerup" );

	model thread PowerupAnimation( model, "y", 30, 2 );
	model thread PowerupAnimation( model, "x", 90, .2 );

	while( isdefined( model ) )
	{
		foreach( player in level.players )
			if( player IsTouching( level.grid[ position ] ) )
			{
				pu_player = player;
				model Delete();
			}

		WAIT_SERVER_FRAME;
	}

	switch( name )
	{
		case "IncreaseLength":     pu_player IncreaseLength();    break;
		case "IncreaseSpeed":      pu_player IncreaseSpeed();     break;
		case "PowerBomb":          pu_player PowerBomb();         break;
		case "Invulnerable":       pu_player Invulnerable();      break;
		case "IncreasedBombCount": pu_player IncreaseBombCount(); break;
	}
}

function PowerupAnimation( model, direction, amount, time )
{
	switch( direction )
	{
		case "y":
			while( isdefined( model ) )
			{
				model MoveZ( amount, time );
				model waittill( "movedone" );
				wait .2;
				model MoveZ( -amount, time );
				model waittill( "movedone" );
				wait .2;
			}
			break;
		case "x":
			while( isdefined( model ) )
			{
				model RotateYaw( amount, time );
				model waittill( "movedone" );
				wait 1;
			}
			break;
	}
}

// |------------------------------------------------------------
// | Powerup Functions
// |------------------------------------------------------------
// |
// | Below are all the functions for the available Powerups:
// |
// | 1. Increase explosion length (no limit)
// | 2. Increase bomb count (limit - 4)
// | 3. Increase speed (limit - 1.4)
// | 4. Power bomb (no limit due to usage)
// | 5. Invulnerable for 10 seconds (no limit due to usage)

function SetExplosionLength( length ) { self.explosionLength = length; }
function GetExplosionLength() { return self.explosionLength; }
function SetMaxBombCount( length ) { self.maxBombCount = length; }
function GetMaxBombCount() { return self.maxBombCount; }

function IncreaseLength() 
{ 
	if( GetExplosionLength() == level.mapWidth ) { self thread HUDNotifyPowerup( "Max power reached!", true ); return; }

	SetExplosionLength( GetExplosionLength() + 1 ); 
	self thread HUDNotifyPowerup( "Power +1", false ); 
}

function IncreaseSpeed() 
{ 
	if( self GetMoveSpeedScale() == 1.4 ) { self thread HUDNotifyPowerup( "Max movespeed reached!", true ); return; }

	self SetMoveSpeedScale( self GetMoveSpeedScale() + 0.2 ); 
	self thread HUDNotifyPowerup( "Speed +0.2", false ); 
}

function IncreaseBombCount() 
{ 
	if( GetMaxBombCount() == 5 ) { self thread HUDNotifyPowerup( "Max bombs reached!", true ); return; }

	SetMaxBombCount( GetMaxBombCount() + 1 ); 
	self thread HUDNotifyPowerup( "Bombs +1", false ); 
}

function PowerBomb() 
{
	if( self.hasPowerBomb ) { self thread HUDNotifyPowerup( "Power bomb already active!", true ); return; }

	self.hasPowerBomb = true; 
	self thread HUDNotifyPowerup( "Power bomb!", false );
}

function Invulnerable()
{
	if( self.invulnerable ) { self thread HUDNotifyPowerup( "Invulnerable already active!", true ); return; }

	self thread HUDNotifyPowerup( "Invulnerable for 10 seconds" );

	for( i = 0; i <= 10; i += 0.1 )
	{
		if( !self.invulnerable ) self.invulnerable = true;
		wait 0.1;
	}

	self.invulnerable = false;
}

// |------------------------------------------------------------
// | HUD Functions
// |------------------------------------------------------------
// |
// | Below are all the functions for HUDs 
// | Call hudDisplayStats onSpawn for player(s)

function HUDNotifyPowerup( text, active )
{
	self notify( "HUD_active" ); // This is so if the user gets a powerup before previous powerup HUD dissapears
    NotifyText = self HUD::CreateFontString( "objective", 2.5 );
    NotifyText HUD::SetPoint( "CENTER", "CENTER", 0, -80 );
    NotifyText.glowAlpha = 1;
    NotifyText.hideWhenInMenu = true;
    NotifyText.glowColor = ( 1.0, 0.0, 0.0 );
    NotifyText.archived = false;
    NotifyText.color = ( 1, 1, 0.6 );
    NotifyText.alpha = 1;
    if( !active ) NotifyText SetText( "^1P^2O^3W^4E^1R^2U^3P^4: ^7" + text );
    else NotifyText SetText( text );

    NotifyText thread DeathDelete( self );
    NotifyText thread ActiveDelete( self );

    wait 4;
    NotifyText Destroy();
    NotifyText = undefined;
}

function DeathDelete( player )
{
    player waittill ( "death" );
    HUD_message::DestroyHudElem( self );
}

function ActiveDelete( player )
{
	player waittill( "HUD_active" );
	HUD_message::DestroyHudElem( self );
}

function HUDDisplayStats()
{
	BombCount = self HUD::CreateFontString( "objective", 2 );
	BombCount HUD::SetPoint( "BOTTOM LEFT", "BOTTOM LEFT", 10, -60 );
	BombCount.hideWhenInMenu = true;

	Power = self HUD::CreateFontString( "objective", 2 );
	Power HUD::SetPoint( "BOTTOM LEFT", "BOTTOM LEFT", 10, -40 );
	Power.hideWhenInMenu = true;

	Speed = self HUD::CreateFontString( "objective", 2 );
	Speed HUD::SetPoint( "BOTTOM LEFT", "BOTTOM LEFT", 10, -20 );
	Speed.hideWhenInMenu = true;

	BombFull = addHUD( self, 10, -80, .5, "left", "bottom", "left", "bottom", 0, 0, 1 );
    BombFull SetShader( "bomb_full", 40, 40 );
    BombFull.hideWhenInMenu = true;

    InvulnerableFull = addHUD( self, 40, -80, .5, "left", "bottom", "left", "bottom", 0, 0, 1 );
    InvulnerableFull SetShader( "invulnerable_full", 35, 35 );
    InvulnerableFull.hideWhenInMenu = true;

	while( true )
	{
		BombCount SetText( "^1Bombs: " + ( GetMaxBombCount() - self.bombCount ) );
		Power SetText( "^2Power: " + GetExplosionLength() );
		Speed SetText( "^4Speed: " + self GetMoveSpeedScale() );

		if( self.hasPowerBomb ) BombFull.alpha = 1;
		else BombFull.alpha = .3;

		if( self.invulnerable ) InvulnerableFull.alpha = 1;
		else InvulnerableFull.alpha = .3;

		WAIT_SERVER_FRAME;
	}

	self waittill( "death" );
	HUD_message::DestroyHUDElem( self );
}

function addHUD( player, x, y, alpha, AlignX, AlignY, horzAlign, vertAlign, vert, fontScale, sort ) 
{
	if( IsPlayer( player ) ) HUD = NewClientHudElem( player );
	else HUD = NewHudElem();

	HUD.x = x;
	HUD.y = y;
	HUD.alpha = alpha;
	HUD.sort = sort;
	HUD.AlignX = AlignX;
	HUD.AlignY = AlignY;
	HUD.horzAlign = horzAlign;
	HUD.vertAlign = vertAlign;
	if( isdefined( vert ) ) HUD.horzAlign = vert;
	if( fontScale != 0 ) HUD.fontScale = fontScale;
	return HUD;
}

// |------------------------------------------------------------
// | EndGame Functions
// |------------------------------------------------------------
// |
// | Below are all the functions for EndGame

function endGame( winner, endReasonText )
{
	if ( game["state"] == "postgame" || level.gameEnded ) return;

	if ( !isdefined( level.disableOutroVisionSet ) || level.disableOutroVisionSet == false ) VisionSetNaked( "mpOutro", 2.0 );
	
	SetMatchFlag( "cg_drawSpectatorMessages", 0 );
	SetMatchFlag( "game_ended", 1 );

	game["state"] = "postgame";
	level.gameEnded = true;
	SetDvar( "g_gameEnded", 1 );
	level.inGracePeriod = false;
	level notify ( "game_ended" );
	level clientfield::set( "game_ended", 1 );
	
	if ( !isdefined( game["overtime_round"] ) || util::wasLastRound() ) game[ "roundsplayed" ]++;
	
	players = level.players;
	bbGameOver = 0;

	if ( util::isOneRound() || util::wasLastRound() ) bbGameOver = 1;

	for ( index = 0; index < players.size; index++ )
	{
		player = players[ index ];
		player globallogic_player::freezePlayerForRoundEnd();
		player thread roundEndDoF( 4.0 );

		player globallogic_ui::freeGameplayHudElems();

		if ( bbGameOver ) player behaviorTracker::Finalize();
	}
	
	if ( globallogic::startNextRound( winner, endReasonText ) ) return;
	
	level.finalGameEnd = true;	
	level.intermission = true;

	music::setmusicstate( "silent" );
	
	util::setClientSysState( "levelNotify", "fkcs" );

	players = level.players;

	for ( index = 0; index < players.size; index++ )
	{
		player = players[ index ];
		
		player notify ( "reset_outcome" );
        player setClientUIVisibilityFlag( "hud_visible", 0 );
	}

	level clientfield::set( "post_game", 1 );

	doEndGameSequence();
	
	if ( isdefined ( level.endGameFunction ) ) level thread [[ level.endGameFunction ]]();
	
	level notify ( "sfade");
	/#print( "game ended" );#/
	
	if ( !isdefined( level.skipGameEnd ) || !level.skipGameEnd ) wait 5.0;
	
	exit_level();
}

function exit_level()
{
	if ( level.exitLevel ) return;
	
	level.exitLevel = true;
	exitLevel( false );
}

function roundEndDOF( time ) { self setDepthOfField( 0, 128, 512, 4000, 6, 1.8 ); }

function doEndGameSequence() 
{
	// need to finish
	ClearPlayerCorpses();
	level thread globallogic::sndSetMatchSnapshot( 3 );
}