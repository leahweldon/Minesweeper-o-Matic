{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

-- This file acts as the main entry point for the Minesweeper project.
-- Its purpose is to import the GUI code from GameUI, then run it.

import GameUI (gameGUI)

main :: IO ()
main = do
    -- Start the Minesweeper GUI by calling 'gameGUI' from GameUI.hs.
    -- Once called, it sets up the Threepenny server and displays the UI in a browser.
    gameGUI
