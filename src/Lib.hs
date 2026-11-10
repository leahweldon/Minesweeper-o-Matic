module Lib (fisherYatesShuffle, sampleN) where

import System.Random      (randomRIO)
import Data.Array.IO      (newListArray, IOArray, readArray, writeArray, getElems)
import Control.Monad      (forM_)

-- The fisherYatesShuffle function takes a list and returns a new list in random order.
-- It uses the Fisher-Yates (aka Knuth) shuffle algorithm, which randomly swaps elements
-- in-place in an IOArray. This gives each permutation an equal chance.
fisherYatesShuffle :: [a] -> IO [a]
fisherYatesShuffle [] = pure []
fisherYatesShuffle arr = do
    let arrLength = length arr
    -- Convert the list into an IOArray so we can swap elements.
    newArray <- newListArray (0, arrLength - 1) arr
    -- For each i from 1..(arrLength - 1), pick a random j between [0..i], swap i and j.
    forM_ [1..arrLength - 1] $ \i -> do
        j <- randomRIO (0, i)
        swapElements i j newArray
    -- Convert the shuffled IOArray back into a normal list.
    getElems newArray

-- swapElements swaps the items in the IOArray at indices i and j.
-- This is the fundamental in-place operation used by the Fisher-Yates shuffle.
swapElements :: Int -> Int -> IOArray Int a -> IO ()
swapElements i j arr = do
    xi <- readArray arr i
    xj <- readArray arr j
    writeArray arr j xi
    writeArray arr i xj

-- sampleN first shuffles the entire list using fisherYatesShuffle,
-- then returns the first N elements of that shuffled list.
-- This is handy if you just want a random subset of size N from a bigger list.
sampleN :: Int -> [a] -> IO [a]
sampleN n xs = do
    shuffled <- fisherYatesShuffle xs
    return (take n shuffled)
