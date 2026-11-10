module Main (main) where

import Control.Exception (try)
import Control.Monad (unless)
import Mine

main :: IO ()
main = do
    testBoardCreation
    testCellBounds
    testAdjacency
    testSingleReveal
    testZeroExpansion
    testFlagging
    testMineReveal
    testVictory
    testSingleClueDeduction
    testSubsetDeduction
    testUnknownBoard
    putStrLn "All Minesweeper tests passed."

assertEqual :: (Eq a, Show a) => String -> a -> a -> IO ()
assertEqual label expected actual =
    unless (expected == actual) $
        error (label ++ ": expected " ++ show expected ++ ", got " ++ show actual)

assertTrue :: String -> Bool -> IO ()
assertTrue label condition = unless condition (error label)

boardWithMines :: (Int, Int) -> [(Int, Int)] -> Board
boardWithMines (rows, cols) mines =
    let empty = Board (rows, cols)
            (replicate rows (replicate cols (Cell (Open 0) Covered)))
        placed = foldl (\board coord -> putCell board (Cell Bomb Covered) coord)
                       empty mines
    in fillAdjCounts placed

countMines :: Board -> Int
countMines (Board _ rows) = length
    [() | row <- rows, Cell Bomb _ <- row]

testBoardCreation :: IO ()
testBoardCreation = do
    board <- initBoard 8 10 15
    assertEqual "number of mines" 15 (countMines board)
    assertEqual "board dimensions" (8, 10) (case board of Board dims _ -> dims)
    rejected <- try (initBoard 2 2 4) :: IO (Either IOError Board)
    assertTrue "invalid mine counts should be rejected" $ case rejected of
        Left _ -> True
        Right _ -> False

testCellBounds :: IO ()
testCellBounds = do
    let board = boardWithMines (2, 2) [(0, 1)]
    assertEqual "negative row" Nothing (getCell board (-1, 0))
    assertEqual "column beyond board" Nothing (getCell board (0, 2))
    assertEqual "out-of-bounds update" board
        (putCell board (Cell Bomb Uncovered) (5, 5))

testAdjacency :: IO ()
testAdjacency = do
    let board = boardWithMines (3, 3) [(0, 0), (2, 2)]
    assertEqual "centre has two neighbouring mines"
        (Just (Cell (Open 2) Covered)) (getCell board (1, 1))
    assertEqual "top-right is clear"
        (Just (Cell (Open 0) Covered)) (getCell board (0, 2))

testSingleReveal :: IO ()
testSingleReveal = do
    let board = boardWithMines (2, 2) [(0, 1)]
        (next, result) = revealCell (0, 0) board
    assertEqual "safe reveal outcome" Continue result
    assertEqual "safe numbered cell" (Just (Cell (Open 1) Uncovered)) (getCell next (0, 0))

testZeroExpansion :: IO ()
testZeroExpansion = do
    let board = boardWithMines (3, 3) [(0, 0)]
        (next, result) = revealCell (2, 2) board
    assertEqual "zero reveal outcome" Continue result
    assertEqual "zero expansion reaches safe border" (Just (Cell (Open 1) Uncovered))
        (getCell next (0, 1))
    assertTrue "all safe cells revealed after expansion" (checkVictory next)

testFlagging :: IO ()
testFlagging = do
    let board = boardWithMines (2, 2) [(0, 1)]
        (marked, _) = toggleFlag (0, 1) board
        (notRevealed, _) = revealCell (0, 1) marked
        (unmarked, _) = toggleFlag (0, 1) marked
    assertEqual "flag covers mine" (Just (Cell Bomb Flagged)) (getCell marked (0, 1))
    assertEqual "flagged cell cannot be revealed" marked notRevealed
    assertEqual "flag can be removed" board unmarked

testMineReveal :: IO ()
testMineReveal = do
    let board = boardWithMines (2, 2) [(0, 1), (1, 0)]
        (next, result) = revealCell (0, 1) board
    assertEqual "mine ends the game" GameOver result
    assertEqual "all mines shown after loss" (Just (Cell Bomb Uncovered)) (getCell next (1, 0))
    assertTrue "exposed mine cannot be victory" (not (checkVictory next))

testVictory :: IO ()
testVictory = do
    let board = boardWithMines (2, 2) [(0, 1)]
        (b1, _) = revealCell (0, 0) board
        (b2, _) = revealCell (1, 0) b1
        (b3, _) = revealCell (1, 1) b2
    assertTrue "unfinished board is not a win" (not (checkVictory b1))
    assertTrue "all safe cells are uncovered" (checkVictory b3)
    assertTrue "empty board is not a win" (not (checkVictory (Board (0, 0) [])))

testSingleClueDeduction :: IO ()
testSingleClueDeduction = do
    let board = boardWithMines (2, 2) [(0, 1)]
        (b1, _) = revealCell (0, 0) board
        (b2, _) = revealCell (1, 0) b1
        (b3, _) = revealCell (1, 1) b2
        (flagged, _) = toggleFlag (0, 1) board
        (clueShown, _) = revealCell (0, 0) flagged
    assertEqual "remaining unknown must be flagged" (Just (PlaceFlag (0, 1)))
        (deduceMove b3)
    assertEqual "satisfied clue permits safe reveal" (Just (Reveal (1, 0)))
        (deduceMove clueShown)

testSubsetDeduction :: IO ()
testSubsetDeduction = do
    let board = boardWithMines (2, 3) [(1, 0)]
        (b1, _) = revealCell (0, 0) board
        (b2, _) = revealCell (0, 1) b1
    assertEqual "overlapping clues determine a safe cell" (Just (Reveal (0, 2)))
        (deduceMove b2)

testUnknownBoard :: IO ()
testUnknownBoard = do
    let board = boardWithMines (2, 2) [(0, 1)]
    assertEqual "no deduction before a clue is exposed" Nothing (deduceMove board)
