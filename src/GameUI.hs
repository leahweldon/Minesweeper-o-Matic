{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

module GameUI (gameGUI) where

import Mine
import Graphics.UI.Threepenny.Core
import qualified Graphics.UI.Threepenny as UI
import qualified Graphics.UI.Threepenny.SVG as SVG

import Control.Monad (void, unless)
import Data.IORef    (newIORef, readIORef, writeIORef, IORef)
import Text.Printf   (printf)

-- KeepS track of different modes the player can be in.
-- StartMode: no mode chosen yet (used when a new board is created).
-- RevealMode: user is currently revealing cells.
-- FlagMode: user is placing flags on suspected bombs.
-- DoneMode: game is over (either won or lost).
data PlayMode
    = StartMode
    | RevealMode
    | FlagMode
    | DoneMode
    deriving (Show, Eq, Ord)

-- The main function that launches the Threepenny-based Minesweeper GUI.
-- Configures server settings and call 'setup' to build interface.
gameGUI :: IO ()
gameGUI = do
    let config = defaultConfig
            { jsPort   = Just 3000
            , jsAddr   = Just "localhost"
            , jsStatic = Just "static"
            }
    startGUI config setup


-- Handles what happens when the user clicks a cell (either to reveal or flag).
cellClicked
    :: Int                       -- row clicked
    -> Int                       -- col clicked
    -> IORef (Board, PlayMode)   -- reference storing (Board, current mode)
    -> UI.Timer                  -- the timer we need to stop if game ends
    -> Element                   -- label on which we display messages (infoLabelEl)
    -> Element                   -- the SVG board container
    -> Window                    -- the main window
    -> UI ()
cellClicked r c stateRef gameTimer infoLabelEl boardContainerEl window = do
    (b, pm) <- liftIO $ readIORef stateRef
    let coords = (r, c)

    case pm of
      DoneMode -> pure ()
      StartMode -> finishReveal (revealCell coords b)
      RevealMode -> finishReveal (revealCell coords b)
      FlagMode -> do
        let (nextBoard, _) = toggleFlag coords b
        liftIO $ writeIORef stateRef (nextBoard, FlagMode)
        redraw ""
  where
    finishReveal (nextBoard, outcome) = case outcome of
      GameOver -> do
        liftIO $ writeIORef stateRef (nextBoard, DoneMode)
        redraw "Boom! You lose :("
        void $ UI.stop gameTimer
      Continue
        | checkVictory nextBoard -> do
            liftIO $ writeIORef stateRef (nextBoard, DoneMode)
            redraw "Hooray, You Win!!"
            void $ UI.stop gameTimer
        | otherwise -> do
            liftIO $ writeIORef stateRef (nextBoard, RevealMode)
            redraw ""

    redraw message = do
      void $ element infoLabelEl # set text message
      drawBoard stateRef boardContainerEl window gameTimer infoLabelEl


-- Draws a single cell in the SVG board.
drawCell
    :: IORef (Board, PlayMode)
    -> Int
    -> Int
    -> Window
    -> UI.Timer
    -> Element
    -> Element
    -> UI Element
drawCell stateRef r c window gameTimer infoLabelEl boardContainerEl = do
    (Board (_, _) grid, _) <- liftIO $ readIORef stateRef

    let bCell = grid !! r !! c      -- the actual BoardCell at (r,c)
    let sz    = 35                 -- each cell is 35x35 px
    let xPos  = c * sz             -- x-position in the SVG
    let yPos  = r * sz             -- y-position in the SVG

    -- We'll place shapes in an SVG group (<g>).
    gEl <- SVG.g
    -- On mouse up, call cellClicked to handle reveal/flag logic.
    on UI.mouseup gEl $ \_ ->
      cellClicked r c stateRef gameTimer infoLabelEl boardContainerEl window

    -- Draw base rectangle of the cell. If it's covered, it has a pinkish fill; else white.
    rect <- SVG.rect
        # set SVG.x (show xPos)
        # set SVG.y (show yPos)
        # set SVG.width  (show sz)
        # set SVG.height (show sz)
        # set SVG.stroke "#ff99dd"
        # set SVG.stroke_width "1"
        # set SVG.fill (case bCell of
                          Cell _ Covered -> "#ffccee"
                          _              -> "#ffffff")

    -- Depending on the cell's state, draw a bomb, a number, or a flag, or nothing extra.
    extra <- case bCell of

      -- If a bomb is uncovered, show a pink circle with a white exclamation mark that miimics a bomb looking
      -- image, looks a little bit cooler than just a circle.
      Cell Bomb Uncovered -> do
        bombCircle <- SVG.circle
            # set SVG.cx (show (xPos + sz `div` 2))
            # set SVG.cy (show (yPos + sz `div` 2))
            # set SVG.r  "10"
            # set SVG.fill "#ff3399"
            # set SVG.stroke "#ffffff"
            # set SVG.stroke_width "1"

        exMark <- SVG.text
            # set SVG.x (show (xPos + sz `div` 2))
            # set SVG.y (show (yPos + sz `div` 2 + 6))
            # set text "!"
            # set (attr "text-anchor") "middle"
            # set (attr "dominant-baseline") "middle"
            # set SVG.font_size "20px"
            # set SVG.font_weight "bold"
            # set SVG.fill "#ffffff"

        return [bombCircle, exMark]

      -- If it's an uncovered number, display it. If it's zero, no text is added.
      Cell (Open n) Uncovered ->
        if n == 0
          then return []
          else do
            txt <- SVG.text
                # set SVG.x (show (xPos + sz `div` 2))
                # set SVG.y (show (yPos + sz `div` 2 + 6))
                # set text (show n)
                # set (attr "text-anchor") "middle"
                # set (attr "dominant-baseline") "middle"
                # set SVG.font_size "20px"
                # set SVG.font_weight "bold"
                # set SVG.fill (numColor n)
            return [txt]

      -- If it's flagged, draw a small rectangle as a pole and a pink pennant on top to look like a little flag!
      Cell _ Flagged -> do
        pole <- SVG.rect
            # set SVG.x (show (xPos + sz `div` 2 - 2))
            # set SVG.y (show (yPos + sz `div` 4))
            # set SVG.width "3"
            # set SVG.height (show (sz `div` 2))
            # set SVG.fill "#cc0066"

        pennant <- SVG.path
            # set (attr "d") "M 0,0 L 15,8 L 0,16 z"
            # set SVG.fill "#ff66cc"
            # set SVG.transform
                  (printf "translate(%d,%d)"
                           (xPos + sz `div` 2 - 2)
                           (yPos + sz `div` 4))
        return [pole, pennant]

      _ -> return []

    let shapes = rect : extra
    void $ element gEl # set children shapes
    return gEl


-- Draws the entire board (all rows and columns) as an SVG.
drawBoard
    :: IORef (Board, PlayMode)
    -> Element
    -> Window
    -> UI.Timer
    -> Element
    -> UI ()
drawBoard stateRef containerEl window gameTimer infoLabelEl = do
    -- Reads the board size and mode from IORef.
    (Board (rows, cols) _, pm) <- liftIO $ readIORef stateRef

    -- Clear the existing children from the container before re-drawing.
    void $ element containerEl # set children []

    -- Each cell is 35 px, so total width is cols*35, height is rows*35.
    let cellSize = 35
    let totalW   = show (cols * cellSize)
    let totalH   = show (rows * cellSize)

    -- Create an SVG root with dotted border, pinkish background.
    svgRoot <- SVG.svg
        # set SVG.width  totalW
        # set SVG.height totalH
        # set style [ ("border","2px dotted #ff66cc")
                    , ("background","#fff2f8")
                    ]

    -- For each row r, for each column c, we call drawCell.
    rowEls <- mapM (\r ->
                mapM (\c ->
                    drawCell stateRef r c window gameTimer infoLabelEl containerEl
                ) [0..cols-1]
              ) [0..rows-1]

    -- Flatten all drawn cells into a single list and add them to svgRoot.
    let allCells = concat rowEls
    void $ element svgRoot # set children allCells

    -- Put svgRoot into containerEl, thus refreshing the board visually.
    void $ element containerEl # set children [svgRoot]


-- The "setup" function builds the user interface and sets up event handlers.
setup :: Window -> UI ()
setup window = do
    -- Load our external CSS for styling to make it look pretty!
    UI.addStyleSheet window "style.css"

    -- The initial landing page with instructions. Hidden later after user clicks "Ready? Let's Play!".
    instructionsDiv <- UI.div
        #. "instructions-container"
        #+ 
        [ UI.h1 #. "title"
             # set text "Welcome to Minesweeper!"
        , UI.p  #. "instructions-paragraph"
             # set text
               ( "How to Win:\n"
               ++ "    The goal is to uncover every safe cell in the grid without clicking a bomb.\n"
               ++ "    Once every non-bomb cell is revealed, you win!\n\n"
               ++ "Instructions:\n"
               ++ "1) Adjust the 'Rows', 'Columns', and 'Mines' sliders to set the board's size.\n"
               ++ "   Then click 'New Board' to generate a new random layout.\n"
               ++ "2) 'Expose Mode': Clicking on a covered cell will uncover it. If it's a bomb, game over!\n"
               ++ "   Otherwise, it shows a number equal to how many bombs are nearby. If zero, it auto-exposes neighbors.\n"
               ++ "3) 'Flag Mode': Clicking on a cell in Flag Mode will place (or remove) a flag, to mark suspected bombs.\n"
               ++ "4) 'Play Move': The game tries to find a guaranteed safe cell logically. If found, it uncovers it.\n"
               ++ "   It checks numbered clues and overlapping constraints for logical moves.\n"
               ++ "   If no certain move is available, it guesses a random covered cell.\n\n"
               ++ "Click 'Ready? Let's Play!' to continue, then 'New Board' to start a new game.\n"
               )
        , UI.button
             #. "start-btn"
             # set UI.id_ "startButton"
             # set text "Ready? Let's Play!"
        ]

    -- mainContent is our main game area, initially hidden until the user leaves the instructions.
    mainContent <- UI.div #. "main-content"
        # set style [("display","none")]

    titleEl <- UI.h1 #. "game-title"
        # set text "Minesweeper-o-Matic"

    -- infoLabelEl is where we put user feedback, e.g. "You triggered a bomb!"
    infoLabelEl <- UI.span #. "info-label"
        # set text ""
        # set style [("margin-left","10px"), ("font-weight","bold")]
        # set UI.id_ "infoLabel"

    -- This will hold the SVG with the board.
    boardContainerEl <- UI.div #. "board-container"
        # set UI.id_ "boardContainer"

    -- Three sliders for rows, columns, and mines, plus labels that show the current value.
    rowsSlider  <- mkSlider "rowsSlider"  8  4  20
    colsSlider  <- mkSlider "colsSlider" 10  5  30
    mineSlider  <- mkSlider "mineSlider" 15  5  50

    rowsValue   <- mkLabel "rowsValue"  "Rows: 8"
    colsValue   <- mkLabel "colsValue"  "Cols: 10"
    mineValue   <- mkLabel "mineValue"  "Mines: 15"

    -- Buttons for new board, reveal mode, flag mode, and an auto-play "Play Move".
    newBoardBtn <- mkBtn "New Board"
    revealBtn   <- mkBtn "Expose Mode"
    flagBtn     <- mkBtn "Flag Mode"
    autoBtn     <- mkBtn "Play Move"

    -- Timer label to show how many seconds have passed on the current board.
    timerLabel <- UI.span
        # set text "0"
        # set style [("margin-left","20px"), ("font-weight","bold"), ("color","#99004d")]

    -- Store time in an IORef, increment it every second using gameTimer.
    timeRef <- liftIO $ newIORef (0 :: Int)

    gameTimer <- UI.timer
        # set UI.interval 1000

    on UI.tick gameTimer $ \_ -> do
        t <- liftIO $ readIORef timeRef
        let t' = t + 1
        liftIO $ writeIORef timeRef t'
        void $ element timerLabel # set text (show t')

    -- Layout row by row: first row for rows slider, second row for columns and so on.
    row1 <- mkRow [ element rowsValue, element rowsSlider ]
    row2 <- mkRow [ element colsValue, element colsSlider ]
    row3 <- mkRow [ element mineValue, element mineSlider ]

    rowButtons <- mkRow
      [ element newBoardBtn
      , element revealBtn
      , element flagBtn
      , element autoBtn
      , element infoLabelEl
      , UI.string " | Time: "
      , element timerLabel
      ]

    void $ element mainContent #+ 
      [ element titleEl
      , element row1
      , element row2
      , element row3
      , element rowButtons
      , element boardContainerEl
      ]

    void $ getBody window #+ [ element instructionsDiv, element mainContent ]

    -- Button that toggles from instructionsDiv to mainContent.
    startBtnMaybe <- getElementById window "startButton"
    case startBtnMaybe of
      Just btn ->
        on UI.click btn $ \_ -> do
          void $ element instructionsDiv # set style [("display","none")]
          void $ element mainContent     # set style [("display","block")]
      Nothing -> return ()

    -- Main (Board, PlayMode) state reference, starts empty with StartMode.
    stateRef <- liftIO $ newIORef (Board (0,0) [], StartMode)

    -- For real-time slider label updates, respond to the 'input' event
    -- (domEvent "input") so the label changes as the user drags the slider.
    on (domEvent "input") rowsSlider $ \_ -> do
      val <- get UI.value rowsSlider
      void $ element rowsValue # set text ("Rows: " ++ val)

    on (domEvent "input") colsSlider $ \_ -> do
      val <- get UI.value colsSlider
      void $ element colsValue # set text ("Cols: " ++ val)

    on (domEvent "input") mineSlider $ \_ -> do
      val <- get UI.value mineSlider
      void $ element mineValue # set text ("Mines: " ++ val)

    -- When user clicks "New Board," read the slider values, create a new random board,
    -- reset the timer, and let the user start playing in StartMode again.
    on UI.click newBoardBtn $ \_ -> do
        rStr <- rowsSlider # get UI.value
        cStr <- colsSlider # get UI.value
        mStr <- mineSlider # get UI.value
        let rn = read rStr
            cn = read cStr
            requestedMines = read mStr
            mn = min requestedMines (rn * cn - 1)

        void $ element mineSlider # set UI.value (show mn)
        void $ element mineValue # set text ("Mines: " ++ show mn)
        newB <- liftIO $ initBoard rn cn mn
        liftIO $ writeIORef stateRef (newB, StartMode)

        liftIO $ writeIORef timeRef 0
        void $ element timerLabel # set text "0"
        UI.stop gameTimer
        UI.start gameTimer

        void $ element infoLabelEl
               # set text "New game has started! Try Expose or Flag mode!"

        void $ drawBoard stateRef boardContainerEl window gameTimer infoLabelEl
        return ()

    -- Switch to "Expose Mode": left-click reveals a cell, if bomb => game over.
    on UI.click revealBtn $ \_ -> do
        (b, pm) <- liftIO $ readIORef stateRef
        if not (boardReady b)
          then void $ element infoLabelEl # set text "Select New Board to begin."
          else unless (pm == DoneMode) $ do
            void $ element infoLabelEl
                   # set text "Expose Mode: left-click to reveal cells."
            liftIO $ writeIORef stateRef (b, RevealMode)
            void $ drawBoard stateRef boardContainerEl window gameTimer infoLabelEl
        return ()

    -- Switch to "Flag Mode": left-click places or removes a flag.
    on UI.click flagBtn $ \_ -> do
        (b, pm) <- liftIO $ readIORef stateRef
        if not (boardReady b)
          then void $ element infoLabelEl # set text "Select New Board to begin."
          else unless (pm == DoneMode) $ do
            void $ element infoLabelEl
                   # set text "Flag Mode: left-click to place flags."
            liftIO $ writeIORef stateRef (b, FlagMode)
            void $ drawBoard stateRef boardContainerEl window gameTimer infoLabelEl
        return ()

    -- "Play Move" tries an automatic solver step. 
    -- If a bomb is triggered => game over, or if the board is now fully safe => victory.
    on UI.click autoBtn $ \_ -> do
        (b, pm) <- liftIO $ readIORef stateRef
        case pm of
          _ | not (boardReady b) ->
            void $ element infoLabelEl # set text "Select New Board to begin."
          DoneMode ->
            void $ element infoLabelEl
                   # set text "Game finished. Try a new board!"
          _ -> do
            (b2, out) <- liftIO $ autoMove b
            case out of
              GameOver -> do
                liftIO $ writeIORef stateRef (b2, DoneMode)
                void $ drawBoard stateRef boardContainerEl window gameTimer infoLabelEl
                void $ element infoLabelEl 
                       # set text "Oh no! You triggered a bomb:("
                void $ UI.stop gameTimer

              Continue ->
                if checkVictory b2
                   then do
                     liftIO $ writeIORef stateRef (b2, DoneMode)
                     void $ drawBoard stateRef boardContainerEl window gameTimer infoLabelEl
                     void $ element infoLabelEl 
                            # set text "You overcame the bombs—Victory!"
                     void $ UI.stop gameTimer
                   else do
                     liftIO $ writeIORef stateRef (b2, pm)
                     void $ drawBoard stateRef boardContainerEl window gameTimer infoLabelEl
                     void $ element infoLabelEl 
                            # set text "Play Move done. Good luck!"
        return ()

    -- Set the window title in the browser tab.
    void $ return window # set title "Minesweeper-o-Matic"


boardReady :: Board -> Bool
boardReady (Board (rows, cols) _) = rows > 0 && cols > 0


-- numColor decides the color of the text for adjacency counts (1..8).
numColor :: Int -> String
numColor n = case n of
    1 -> "#cc0066"
    2 -> "#ff3385"
    3 -> "#ff6699"
    4 -> "#ff80b3"
    5 -> "#cc0080"
    6 -> "#ff1ab3"
    7 -> "#99004d"
    8 -> "#ff4da6"
    _ -> "#e6005c"


-- Helper functions to make sliders, labels, buttons, and layout rows.

mkSlider :: String -> Int -> Int -> Int -> UI Element
mkSlider sid initialVal minVal maxVal = do
    s <- UI.input
        # set UI.type_ "range"
        # set UI.id_ sid
        # set (attr "min") (show minVal)
        # set (attr "max") (show maxVal)
        # set (attr "value") (show initialVal)
        # set style [("margin","0 6px")]
    return s

mkLabel :: String -> String -> UI Element
mkLabel lid initialTxt = do
    l <- UI.span
        # set UI.id_ lid
        # set text initialTxt
        # set style [("margin-right","10px"), ("font-weight","bold")]
    return l

mkBtn :: String -> UI Element
mkBtn lbl = do
    b <- UI.button
        # set text lbl
        # set style [("margin","0 8px"), ("padding","4px 8px"), ("cursor","pointer")]
    return b

mkRow :: [UI Element] -> UI Element
mkRow subs = do
    rowDiv <- UI.div
        # set style [("margin-top","10px")]
    built <- sequence subs
    void $ element rowDiv #+ map element built
    return rowDiv
