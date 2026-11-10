module Mine
    ( CellKind(..)
    , Display(..)
    , BoardCell(..)
    , Dimension
    , Board(..)
    , Outcome(..)
    , Move(..)
    , initBoard
    , fillAdjCounts
    , getCell
    , putCell
    , countBombs
    , revealCell
    , toggleFlag
    , checkVictory
    , deduceMove
    , autoMove
    ) where

import Data.List (foldl')
import Data.Maybe (listToMaybe)
import qualified Data.Set as Set
import System.Random (randomRIO)
import Lib (sampleN)

-- A cell's contents are independent of whether the player can see them.
data CellKind = Bomb | Open Int
    deriving (Show, Eq, Ord)

data Display = Covered | Uncovered | Flagged
    deriving (Show, Eq, Ord)

data BoardCell = Cell CellKind Display
    deriving (Show, Eq, Ord)

type Dimension = (Int, Int)
type Coord = (Int, Int)

data Board = Board Dimension [[BoardCell]]
    deriving (Show, Eq, Ord)

data Outcome = Continue | GameOver
    deriving (Show, Eq, Ord)

data Move = Reveal Coord | PlaceFlag Coord
    deriving (Show, Eq, Ord)

-- Place distinct mines at random and cache the adjacent-mine counts.
initBoard :: Int -> Int -> Int -> IO Board
initBoard rows cols bombCount
    | rows <= 0 || cols <= 0 = ioError (userError "Board dimensions must be positive")
    | bombCount < 0 || bombCount >= rows * cols =
        ioError (userError "Mine count must leave at least one safe cell")
    | otherwise = do
        bombCoords <- sampleN bombCount
            [(r, c) | r <- [0 .. rows - 1], c <- [0 .. cols - 1]]
        let blank = Board (rows, cols)
                (replicate rows (replicate cols (Cell (Open 0) Covered)))
            withBombs = foldl'
                (\board coord -> putCell board (Cell Bomb Covered) coord)
                blank bombCoords
        pure (fillAdjCounts withBombs)

fillAdjCounts :: Board -> Board
fillAdjCounts board@(Board (rows, cols) _) =
    Board (rows, cols)
        [ [ fillCell (r, c) | c <- [0 .. cols - 1] ]
        | r <- [0 .. rows - 1]
        ]
  where
    fillCell coord = case getCell board coord of
        Just (Cell Bomb display) -> Cell Bomb display
        Just (Cell (Open _) display) -> Cell (Open (countBombs board coord)) display
        Nothing -> Cell (Open 0) Covered

getCell :: Board -> Coord -> Maybe BoardCell
getCell (Board (rows, cols) grid) (r, c)
    | r < 0 || r >= rows || c < 0 || c >= cols = Nothing
    | otherwise = do
        row <- atMay r grid
        atMay c row
  where
    atMay index xs = listToMaybe (drop index xs)

putCell :: Board -> BoardCell -> Coord -> Board
putCell board@(Board dims@(rows, cols) grid) newCell (r, c)
    | r < 0 || r >= rows || c < 0 || c >= cols = board
    | otherwise = Board dims
        [ if rowIndex == r then replaceAt c newCell row else row
        | (rowIndex, row) <- zip [0 ..] grid
        ]
  where
    replaceAt index value xs =
        [if position == index then value else old | (position, old) <- zip [0 ..] xs]

neighbors :: Board -> Coord -> [Coord]
neighbors (Board (rows, cols) _) (r, c) =
    [ (rr, cc)
    | dr <- [-1 .. 1], dc <- [-1 .. 1]
    , (dr, dc) /= (0, 0)
    , let rr = r + dr, let cc = c + dc
    , rr >= 0, rr < rows, cc >= 0, cc < cols
    ]

allCoords :: Board -> [Coord]
allCoords (Board (rows, cols) _) =
    [(r, c) | r <- [0 .. rows - 1], c <- [0 .. cols - 1]]

countBombs :: Board -> Coord -> Int
countBombs board coord = length
    [ ()
    | adjacent <- neighbors board coord
    , Just (Cell Bomb _) <- [getCell board adjacent]
    ]

-- A zero-valued cell uncovers its connected empty region and numbered border.
revealCell :: Coord -> Board -> (Board, Outcome)
revealCell coord board = case getCell board coord of
    Just (Cell Bomb Covered) -> (revealAllBombs board, GameOver)
    Just (Cell (Open n) Covered) ->
        let uncovered = putCell board (Cell (Open n) Uncovered) coord
        in if n == 0 then (expandZero uncovered coord, Continue)
                     else (uncovered, Continue)
    _ -> (board, Continue)

expandZero :: Board -> Coord -> Board
expandZero board coord = foldl' revealNeighbor board (neighbors board coord)
  where
    revealNeighbor current adjacent = fst (revealCell adjacent current)

revealAllBombs :: Board -> Board
revealAllBombs (Board dims grid) = Board dims (map (map uncover) grid)
  where
    uncover (Cell Bomb Covered) = Cell Bomb Uncovered
    uncover cell = cell

toggleFlag :: Coord -> Board -> (Board, Outcome)
toggleFlag coord board = case getCell board coord of
    Just (Cell kind Covered) -> (putCell board (Cell kind Flagged) coord, Continue)
    Just (Cell kind Flagged) -> (putCell board (Cell kind Covered) coord, Continue)
    _ -> (board, Continue)

-- A game is won when every safe cell is exposed and no bomb was exposed.
checkVictory :: Board -> Bool
checkVictory (Board (rows, cols) grid) =
    rows > 0 && cols > 0 && length grid == rows
        && all ((== cols) . length) grid && all (all complete) grid
  where
    complete (Cell Bomb Uncovered) = False
    complete (Cell Bomb _) = True
    complete (Cell (Open _) Uncovered) = True
    complete _ = False

-- Each numbered clue constrains its still-covered neighbours.
-- A marked flag is treated as a mine for the purposes of deduction.
type Clue = (Set.Set Coord, Int)

clues :: Board -> [Clue]
clues board =
    [ (covered, remaining)
    | coord <- allCoords board
    , Just (Cell (Open n) Uncovered) <- [getCell board coord]
    , let adjacent = neighbors board coord
    , let covered = Set.fromList
              [p | p <- adjacent, Just (Cell _ Covered) <- [getCell board p]]
    , let flagged = length
              [() | p <- adjacent, Just (Cell _ Flagged) <- [getCell board p]]
    , let remaining = n - flagged
    , remaining >= 0
    , remaining <= Set.size covered
    , not (Set.null covered)
    ]

-- A clue with no remaining mines permits reveals; one where every
-- remaining neighbour is a mine permits flags.
singleClueMoves :: Clue -> [Move]
singleClueMoves (covered, remaining)
    | remaining == 0 = map Reveal (Set.toAscList covered)
    | remaining == Set.size covered = map PlaceFlag (Set.toAscList covered)
    | otherwise = []

-- If one clue's unknown cells are a strict subset of another's, the
-- difference has a known number of mines. This also handles 1-2 patterns.
subsetMoves :: Clue -> Clue -> [Move]
subsetMoves (small, smallMines) (large, largeMines)
    | not (Set.isProperSubsetOf small large) = []
    | differenceMines == 0 = map Reveal (Set.toAscList difference)
    | differenceMines == Set.size difference =
        map PlaceFlag (Set.toAscList difference)
    | otherwise = []
  where
    difference = Set.difference large small
    differenceMines = largeMines - smallMines

-- Prefer a logically determined reveal, followed by a logically determined flag.
deduceMove :: Board -> Maybe Move
deduceMove board =
    let constraints = clues board
        directMoves = concatMap singleClueMoves constraints
        overlappingMoves =
            [ move
            | first <- constraints
            , second <- constraints
            , move <- subsetMoves first second
            ]
        candidates = directMoves ++ overlappingMoves
        reveals = [move | move@(Reveal _) <- candidates]
        flags = [move | move@(PlaceFlag _) <- candidates]
    in listToMaybe (reveals ++ flags)

applyMove :: Move -> Board -> (Board, Outcome)
applyMove (Reveal coord) board = revealCell coord board
applyMove (PlaceFlag coord) board = toggleFlag coord board

-- When no deduction is available, a covered cell is selected at random.
-- The player can lose if that guess contains a mine.
autoMove :: Board -> IO (Board, Outcome)
autoMove board = case deduceMove board of
    Just move -> pure (applyMove move board)
    Nothing -> case coveredCells of
        [] -> pure (board, Continue)
        _ -> do
            index <- randomRIO (0, length coveredCells - 1)
            pure (revealCell (coveredCells !! index) board)
  where
    coveredCells =
        [coord | coord <- allCoords board, Just (Cell _ Covered) <- [getCell board coord]]
