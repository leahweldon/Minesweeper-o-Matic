module Main (main) where

-- Plays complete games using only the Play Move assistant and reports how
-- often it clears the board, how many of its moves were logical deductions
-- and how many guesses a typical game needed.
--
--   stack bench                                  -- 1000 games per board
--   stack bench --benchmark-arguments "200 7"    -- 200 games, seed 7

import Control.Monad (replicateM)
import Mine
import System.Environment (getArgs)
import System.Random (mkStdGen, setStdGen)
import Text.Printf (printf)

data Game = Game
    { gameWon     :: Bool
    , openingSafe :: Bool
    , deductions  :: Int
    , guesses     :: Int
    }

boards :: [(String, Int, Int, Int)]
boards =
    [ ("Beginner",     9,  9, 10)
    , ("Default",      8, 10, 15)
    , ("Intermediate", 16, 16, 40)
    , ("Largest",      20, 30, 50)
    ]

playGame :: Board -> IO Game
playGame = go True 0 0
  where
    go opening deduced guessed board = do
        let isGuess = deduceMove board == Nothing
            deduced' = if isGuess then deduced else deduced + 1
            guessed' = if isGuess then guessed + 1 else guessed
        (next, outcome) <- autoMove board
        case outcome of
            GameOver -> pure (Game False (not opening) deduced' guessed')
            Continue
                | checkVictory next -> pure (Game True True deduced' guessed')
                | next == board -> pure (Game False True deduced' guessed')
                | otherwise -> go False deduced' guessed' next

percent :: Int -> Int -> Double
percent part whole
    | whole == 0 = 0
    | otherwise = 100 * fromIntegral part / fromIntegral whole

main :: IO ()
main = do
    args <- getArgs
    let (games, seed) = case map read args of
            [n, s] -> (n, s)
            [n] -> (n, 2025)
            _ -> (1000, 2025)
    setStdGen (mkStdGen seed)
    printf "Solver benchmark: %d games per board, seed %d\n\n" games seed
    putStrLn "| Board | Size | Mines | Win rate | Win rate after a safe opening | Moves deduced | Guesses per game |"
    putStrLn "|---|---|---:|---:|---:|---:|---:|"
    mapM_ (runBoard games) boards

runBoard :: Int -> (String, Int, Int, Int) -> IO ()
runBoard games (name, rows, cols, mines) = do
    results <- replicateM games (initBoard rows cols mines >>= playGame)
    let wins = length (filter gameWon results)
        safeOpenings = filter openingSafe results
        safeWins = length (filter gameWon safeOpenings)
        deduced = sum (map deductions results)
        guessed = sum (map guesses results)
    printf "| %s | %d x %d | %d | %.1f%% | %.1f%% | %.1f%% | %.2f |\n"
        name rows cols mines
        (percent wins games)
        (percent safeWins (length safeOpenings))
        (percent deduced (deduced + guessed))
        (fromIntegral guessed / fromIntegral games :: Double)
