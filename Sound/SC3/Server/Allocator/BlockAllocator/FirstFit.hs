{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}
module Sound.SC3.Server.Allocator.BlockAllocator.FirstFit
  (
    FirstFitAllocator
  , Sorting(..)
  , Coalescing(..)
  , cons
  , addressFit
  , bestFit
  , worstFit
  ) where

import           Control.Arrow (first)
import           Control.Failure (Failure, failure)
import           Control.Monad (liftM)
import           Sound.SC3.Server.Allocator (AllocFailure(..), Id, IdAllocator(..), RangeAllocator(..), Statistics(..))
import           Sound.SC3.Server.Allocator.Range (Range)
import qualified Sound.SC3.Server.Allocator.Range as Range
import           Sound.SC3.Server.Allocator.BlockAllocator.FreeList (FreeList, Sorting(..))
import qualified Sound.SC3.Server.Allocator.BlockAllocator.FreeList as FreeList

data Coalescing = NoCoalescing | LazyCoalescing deriving (Enum, Eq, Show)

data FirstFitAllocator i = FirstFitAllocator {
    coalescing :: Coalescing
  , available :: !Int
  , used :: !Int
  , freeList :: !(FreeList i)
  } deriving (Eq, Show)

cons :: Integral i => Sorting -> Coalescing -> Range i -> FirstFitAllocator i
cons s c r = FirstFitAllocator c (fromIntegral (Range.size r)) 0 (FreeList.singleton s r)

addressFit :: Integral i => Coalescing -> Range i -> FirstFitAllocator i
addressFit = cons Address

bestFit :: Integral i => Coalescing -> Range i -> FirstFitAllocator i
bestFit = cons IncreasingSize

worstFit :: Integral i => Coalescing -> Range i -> FirstFitAllocator i
worstFit = cons DecreasingSize

_alloc :: (Integral i, Failure AllocFailure m) => Int -> FirstFitAllocator i -> m (Range i, FirstFitAllocator i)
_alloc n a =
    case FreeList.alloc fits (freeList a) of
        Nothing -> case coalescing a of
                    NoCoalescing ->
                        failure NoFreeIds
                    LazyCoalescing ->
                        case FreeList.alloc fits (FreeList.coalesce (freeList a)) of
                            Nothing -> failure NoFreeIds
                            Just (r, l) -> alloc r l
        Just (r, l) -> alloc r l
    where
        fits r = Range.size r >= n
        alloc r l =
            if Range.size r == n
            then return (r, a { freeList = l
                              , used = used a + n })
            else let (r1, r2) = Range.split n r
                 in return (r1, a { freeList = FreeList.insert r2 l
                                  , used = used a + n })

_free :: (Integral i, Failure AllocFailure m) => Range i -> FirstFitAllocator i -> m (FirstFitAllocator i)
_free r a =
    let u = used a - fromIntegral (Range.size r)
    in if u < 0
       then failure InvalidId
       else return a { freeList = FreeList.insert r (freeList a)
                     , used = u }

_statistics :: (Integral i) => FirstFitAllocator i -> Statistics
_statistics a =
    Statistics {
        numAvailable = available a
      , numFree = available a - used a
      , numUsed = used a }

instance (Integral i) => IdAllocator (FirstFitAllocator i) where
    type Id (FirstFitAllocator i) = i
    alloc = liftM (first Range.begin) . _alloc 1
    free = _free . Range.sized 1
    statistics = _statistics

instance (Integral i) => RangeAllocator (FirstFitAllocator i) where
    allocRange = _alloc
    freeRange = _free
