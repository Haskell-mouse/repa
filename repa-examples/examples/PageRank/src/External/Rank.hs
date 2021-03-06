
module External.Rank
        (rankExternal)
where
import External.Count
import External.Step
import External.Titles
import Page
import System.IO
import System.Directory
import Control.Monad
import Prelude                                  as P
import qualified Data.Vector.Unboxed            as U


-- | Perform some iterations of the PageRank algorithm.
--   This is an external verison of the algorithm that runs in constant space.
--   We need to store the old and new versions of the dense ranks vector, 
--   but the new ranks are accumulated incrementally from the links file.
--   We don't try to read the whole links file into memory at the same time.
--  
rankExternal 
        :: Int                  -- ^ Number of iterations to run.
        -> FilePath             -- ^ Path to links file.
        -> FilePath             -- ^ Path to titles file.
        -> IO ()

rankExternal steps pagesPath titlesPath
 = do   (lineCount, maxPageId)  <- countPages pagesPath
        let !pageCount  = maxPageId + 1
        let !ranks      = initialRanks pageCount
        pageRank steps pagesPath titlesPath lineCount pageCount ranks


-- | Construct the initial ranks vector.
initialRanks :: Int -> U.Vector Rank
initialRanks pageCount
 = let  !startRank   = 1 / fromIntegral pageCount
   in   U.replicate pageCount startRank
{-# NOINLINE initialRanks #-}
--  NOINLINE so we can see how much data this function allocates when profiling.


-- | Run several iterations of the external PageRank algorithm.
pageRank :: Int                 -- ^ Number of iterations to run.
        -> FilePath             -- ^ Path to links file.
        -> FilePath             -- ^ Path to titles file.
        -> Int                  -- ^ Total number of lines in the file.
        -> Int                  -- ^ Maximum Page Id
        -> U.Vector Rank        -- ^ Initial pageranks.     
        -> IO ()

pageRank maxIters pageFile titlesFile lineCount maxPageId ranks0
 = go maxIters ranks0
 where  go 0 !ranks
         = do   
                -- Show the page with the maximum rank.
                let rankMaxIx   = U.maxIndex ranks
                let rankMax     = ranks U.! rankMaxIx
                putStrLn $ "  high ix    : "  ++ show rankMaxIx
                putStrLn $ "  high rank  : "  ++ show rankMax

                -- Write out the pages with the top few ranks.
                putStrLn $ "* Writing top ranks."
                let topRanks    = slurpTopRanks rankMax ranks

                -- Ensure the output directory exists.
                exists          <- doesDirectoryExist "out"
                when (not exists)
                 $ createDirectory "out"

                -- Write out the titles of the top few pages.
                mergeRanks ("out/final.ranks") titlesFile topRanks 

        go !i !ranks
         = do   putStr "\n"
                putStrLn $ "* Step " ++ show i

                -- Run a single step of the algorithm.
                ranks1   <- stepExternal pageFile lineCount maxPageId ranks

                -- Sum up the ranks for all the pages, 
                -- this should be very close to 1, minus some some round-off error.
                let rankSum     = U.sum ranks1
                putStrLn $ "  rank sum   : "  ++ show rankSum
                go (i - 1) ranks1

