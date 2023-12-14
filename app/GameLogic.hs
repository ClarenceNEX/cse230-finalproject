{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TemplateHaskell #-}

module GameLogic where

import Brick (str)
import Data.Map (insert, update)
import Debug (appendKeyValueLog, appendLogsToGame)
import System.Random (randomRIO)
import Types
import Utils

-- current implementation only checks whether two monsters are at the
-- same position. An corner case is that two (different) monster may
-- randomly walk to the same position. And in that case, when calling
-- gameMonsterEqual to remove the defeated monter, two monsters will
-- all be removed.
-- TODO: fix the corner case

-- Sleep Event
sleepEvent :: GameEvent
sleepEvent =
  GEvent
    { eventX = 5,
      eventY = 5,
      name = "sleep!",
      description = "Sleeping will help recover HP",
      choices =
        [ GChoice
            { title = "sleep for 10 hours",
              effect = \g -> g {hp = hp g + 2}
            },
          GChoice
            { title = "sleep for 5 hours",
              effect = \g -> g {hp = hp g + 1}
            }
        ],
      icon = str "⏾",
      isused = False
    }

-- Monster Encounter
goblinRaiderEvent :: GameEvent
goblinRaiderEvent =
  GEvent
    { eventX = -1,
      eventY = -1,
      name = "Goblin Raider",
      description = "A sneaky Goblin Raider jumps out!",
      choices = [fightChoice, useItemChoice, fleeChoice],
      icon = str "G",
      isused = False
    }

forestNymphEvent :: GameEvent
forestNymphEvent =
  GEvent
    { eventX = -1,
      eventY = -1,
      name = "Forest Nymph",
      description = "A mystical Forest Nymph appears!",
      choices = [fightChoice, useItemChoice, fleeChoice],
      icon = str "F",
      isused = False
    }

mountainTrollEvent :: GameEvent
mountainTrollEvent =
  GEvent
    { eventX = -1,
      eventY = -1,
      name = "Mountain Troll",
      description = "A formidable Mountain Troll blocks your path!",
      choices = [fightChoice, useItemChoice, fleeChoice],
      icon = str "T",
      isused = False
    }

shadowAssassinEvent :: GameEvent
shadowAssassinEvent =
  GEvent
    { eventX = -1,
      eventY = -1,
      name = "Shadow Assassin",
      description = "A deadly Shadow Assassin emerges from the shadows!",
      choices = [fightChoice, useItemChoice, fleeChoice],
      icon = str "S",
      isused = False
    }

gameMonsterEqual :: Monster -> Monster -> Bool
gameMonsterEqual m1 m2 =
  monsterPosX m1 == monsterPosX m2
    && monsterPosY m1 == monsterPosY m2

fightChoice :: EventChoice
fightChoice = GChoice {title = "Fight", effect = fightMonster}

useItemChoice :: EventChoice
useItemChoice = GChoice {title = "Use Item", effect = useItem}

fleeChoice :: EventChoice
fleeChoice = GChoice {title = "Flee", effect = flee}

updateGameState :: Game -> Game
updateGameState game =
  if hp game <= 0
    then game {gameOver = True}
    else game

fightMonster :: Game -> Game
fightMonster game =
  updateGameState $
    case inMonster game of
      Just monster ->
        let currentMonster = monster
            newPlayerHp = max 0 (hp game - monsterAttack monster)
            newMonsterHp = max 0 (monsterHp monster - attack game)
            updatedMonster = monster {monsterHp = newMonsterHp}
            updatedMonsters =
              replaceMonsterInList
                monster
                updatedMonster
                ( getCurrentRegionMonsters game
                )
            -- gameUpdatedMonster = game {monsters = updatedMonsters}
            isMonsterDefeated = newMonsterHp <= 0
            finalMonsters =
              if isMonsterDefeated
                then filter (not . gameMonsterEqual monster) updatedMonsters
                else getCurrentRegionMonsters game
            gameOverUpdate = hp game == 0
            bonusGain = getBonusForMonster (monsterName monster)
            -- remove the defeated monster (not the monster event!)
            -- Ideally, we can add a type in event to indicate this is an monster (that can move!).
            -- Then we can remove the corresponding event for the monster
            -- But in current code, monsters are represented as another type (Monster), which all share
            -- the same monsterEncounterEvent (which will not be rendered in the map).
            -- To remove a monster in map, we need to remove it from the monsters, not events.
            -- also set inEvent to Nothing, otherwise, even if the monster is defeated, the UI (event bar) will not be updated
            -- TODO: fix the corner case, where multiple monsters are at the same position. In that case, we cannot set inEvent to Nothing
            evt = if isMonsterDefeated then Nothing else inEvent game
            updatedGame = if isMonsterDefeated then applyBonus bonusGain game else game
         in updatedGame
              { hp = newPlayerHp,
                monstersMap = insert (getMapRegionCoord (posX game, posY game)) finalMonsters (monstersMap game),
                gameOver = gameOverUpdate,
                inEvent = evt,
                -- need to update the inMonster. Otherwise, it still points to the old monster (whose hp is not decreased yet)
                inMonster = if isMonsterDefeated then Nothing else Just updatedMonster,
                inBattle = not isMonsterDefeated -- 设置 inBattle 根据怪物是否被击败
              }
      Nothing -> game

applyBonus :: Bonus -> Game -> Game
applyBonus bonus game =
  -- define how bonuses are applied
  case bonus of
    NoBonus -> game
    HPBonus bonusAmount -> game {hp = min 100 (hp game + bonusAmount)}
    AttackBonus bonusAmount -> game {attack = attack game + bonusAmount}
    ShieldBonus bonusAmount -> game {shield = min 100 (shield game + bonusAmount)}
    SwordBonus bonusAmount -> game {sword = sword game + bonusAmount}

getBonusForMonster :: String -> Bonus
getBonusForMonster monsterName =
  case monsterName of
    "Goblin Raider" -> ShieldBonus 5
    "Forest Nymph" -> SwordBonus 3
    "Mountain Troll" -> HPBonus 10
    "Shadow Assassin" -> AttackBonus 4
    _ -> NoBonus

replaceMonsterInList :: Monster -> Monster -> [Monster] -> [Monster]
replaceMonsterInList oldMonster newMonster = map (\m -> if gameMonsterEqual m oldMonster then newMonster else m)

useItem :: Game -> Game
useItem game =
  let healthPotionEffect = 20
      newHp = min 100 (hp game + healthPotionEffect)
   in game {hp = newHp}

flee :: Game -> Game
flee game = game {hp = max 0 (hp game - 5), inEvent = Nothing, inBattle = False}

moveMonster :: Monster -> Game -> IO Monster
moveMonster monster game = do
  direction <- randomRIO (1, 4) :: IO Int
  let (dx, dy) = case direction of
        1 -> (0, 1) -- Move up
        2 -> (0, -1) -- Move down
        3 -> (-1, 0) -- Move left
        4 -> (1, 0) -- Move right
      newX = monsterPosX monster + dx
      newY = monsterPosY monster + dy
      isMountain = any (\m -> mountainPosX m == newX && mountainPosY m == newY) (getMapRegionMountains (newX, newY) game)
  if isMountain
    then return monster -- 如果新位置有山脉，怪物保持不动
    -- TODO: change the monsterMap if the monster goes to another region of the map
    else return $ monster {monsterPosX = newX, monsterPosY = newY}

-- Treasure Chest
treasureChest :: GameEvent
treasureChest =
  GEvent
    { eventX = 10,
      eventY = 15,
      name = "Treasure Chest",
      description = "You've found a treasure chest!",
      choices = [openChestChoice],
      icon = str "⛝",
      isused = False
    }

openChestChoice :: EventChoice
openChestChoice =
  GChoice
    { title = "Open Chest",
      effect = openChest
    }

openChest :: Game -> Game
openChest game =
  if even (posX game + posY game) -- Using player's position to determine the outcome
    then game {hp = min 150 (hp game + healthBonus)} -- Even position sums give health
    else
      if posX game `mod` 3 == 0
        then game {shield = min 100 (shield game + shieldBonus)} -- Position x divisible by 3 gives shield
        else game {hp = max 0 (hp game - trapDamage)} -- Other positions are traps
  where
    healthBonus = 20
    shieldBonus = 15
    trapDamage = 10

-- Ancient Shrine
ancientShrineEncounter :: GameEvent
ancientShrineEncounter =
  GEvent
    { eventX = 4,
      eventY = 6,
      name = "Ancient Shrine Encounter",
      description = "You encounter a mysterious ancient shrine in the forest.",
      choices = [offerStrengthChoice, meditateChoice],
      icon = str "۩",
      isused = False
    }

offerStrengthChoice :: EventChoice
offerStrengthChoice =
  GChoice
    { title = "Offer Strength",
      effect = \game ->
        if attack game > 3
          then game {attack = attack game - 3, sword = sword game + 10}
          else game
    }

meditateChoice :: EventChoice
meditateChoice =
  GChoice
    { title = "Meditate",
      effect = \game -> game {shield = shield game + 5}
    }

-- Mysterious Traveler
mysteriousTraveler :: GameEvent
mysteriousTraveler =
  GEvent
    { eventX = 9,
      eventY = 8,
      name = "Mysterious Traveler",
      description = "You meet a mysterious traveler at a crossroads.",
      choices = [shareMealChoice, trainTogetherChoice],
      icon = str "⚇",
      isused = False
    }

shareMealChoice :: EventChoice
shareMealChoice =
  GChoice
    { title = "Share a meal",
      effect = \game -> game {hp = hp game - 10, shield = shield game + 10}
    }

trainTogetherChoice :: EventChoice
trainTogetherChoice =
  GChoice
    { title = "Train together",
      effect = \game -> game {attack = attack game + 3}
    }

-- Lost Treasure Chest
lostTreasureChest :: GameEvent
lostTreasureChest =
  GEvent
    { eventX = 12,
      eventY = 17,
      name = "Lost Treasure Chest",
      description = "You find a lost treasure chest in a hidden cave.",
      choices = [forceOpenChoice, carefullyUnlockChoice],
      icon = str "⛝",
      isused = False
    }

forceOpenChoice :: EventChoice
forceOpenChoice =
  GChoice
    { title = "Force open",
      effect = \game ->
        if attack game > 20
          then game {hp = hp game + 5, shield = shield game + 5}
          else game
    }

carefullyUnlockChoice :: EventChoice
carefullyUnlockChoice =
  GChoice
    { title = "Carefully unlock",
      effect = \game ->
        if sword game > 15
          then game {hp = hp game + 10} -- Assuming finding gold impacts hp positively
          else game
    }

--  Enchanted Lake
enchantedLake :: GameEvent
enchantedLake =
  GEvent
    { eventX = 18,
      eventY = 14,
      name = "Enchanted Lake",
      description = "You discover an enchanted lake that glows under the moonlight.",
      choices = [batheInLakeChoice, searchAroundChoice],
      icon = str "〰",
      isused = False
    }

batheInLakeChoice :: EventChoice
batheInLakeChoice =
  GChoice
    { title = "Bathe in the lake",
      effect = \game -> game {hp = 150} -- Assuming full heal plus extra HP
    }

searchAroundChoice :: EventChoice
searchAroundChoice =
  GChoice
    { title = "Search around the lake",
      effect = \game -> game -- Implementation depends on what the random bonuses are
    }

-- Ancient Library
ancientLibrary :: GameEvent
ancientLibrary =
  GEvent
    { eventX = 22,
      eventY = 25,
      name = "The Ancient Library",
      description = "You find yourself in a library filled with ancient tomes.",
      choices = [studyAncientTomesChoice, searchForSecretsChoice],
      icon = str "𐂨",
      isused = False
    }

studyAncientTomesChoice :: EventChoice
studyAncientTomesChoice =
  GChoice
    { title = "Study ancient tomes",
      effect = \game ->
        if sword game >= 10 -- Adjust the threshold for 'high Sword' as needed
          then game {attack = attack game + 5}
          else game
    }

searchForSecretsChoice :: EventChoice
searchForSecretsChoice =
  GChoice
    { title = "Search for secret passages",
      effect = \game -> game -- Effect depends on how you want to handle map discovery
    }


-- Final Confrontation: The Dark Overlord's Lair Event
finalConfrontation :: GameEvent
finalConfrontation =
  GEvent
    { eventX = 19,
      eventY = 8,
      name = "Final Confrontation: The Dark Overlord's Lair",
      description = "You stand before the lair of the Dark Overlord, ready for the final battle.",
      choices = [directAssaultChoice, sneakAttackChoice], -- Added sneak attack choice
      icon = str "Ӝ",
      isused = False
    }

-- Direct Assault Choice
directAssaultChoice :: EventChoice
directAssaultChoice =
  GChoice
    { title = "Direct assault",
      effect = \game ->
        let playerAttack = attack game + (sword game `div` 2) -- 50% bonus from sword
            newMonsterHp = finalMonsterHp game - playerAttack
            newPlayerHp = hp game - finalMonsterAttack game
         in if newMonsterHp <= 0
              then game {winner = True}
              else game {finalMonsterHp = newMonsterHp, hp = newPlayerHp, loser = newPlayerHp <= 0}
    }

-- Sneak Attack Choice
sneakAttackChoice :: EventChoice
sneakAttackChoice =
  GChoice
    { title = "Sneak attack",
      effect = \game ->
        let playerAttack = attack game + (shield game `div` 2) -- 50% bonus from shield
            newMonsterHp = finalMonsterHp game - playerAttack
            newPlayerHp = hp game - finalMonsterAttack game
         in if newMonsterHp <= 0
              then game {winner = True}
              else game {finalMonsterHp = newMonsterHp, hp = newPlayerHp, loser = newPlayerHp <= 0}
    }
