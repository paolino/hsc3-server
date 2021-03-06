{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}

module Sound.SC3.Server.Allocator (
  -- *Allocation errors
  AllocFailure(..)
  -- * Allocator statistics
, Statistics(..)
, percentFree
, percentUsed
  -- * Allocator classes
, IdAllocator(..)
, allocMany
, freeMany
, RangeAllocator(..)
) where

import           Control.Exception (Exception)
import           Control.Failure (Failure)
import           Data.Typeable (Typeable)
import           Sound.SC3.Server.Allocator.Range

-- | Failure type for allocators.
data AllocFailure =
    NoFreeIds   -- ^ There are no free ids left in the allocator.
  | InvalidId   -- ^ The id being released has not been allocated by this allocator.
  deriving (Show, Typeable)

instance Exception AllocFailure

-- | Simple allocator usage statistics.
data Statistics = Statistics {
    numAvailable :: Int     -- ^ Total number of available identifiers
  , numFree :: Int          -- ^ Number of currently available identifiers
  , numUsed :: Int          -- ^ Number of identifiers currently in use
  } deriving (Eq, Show)

-- | Percentage of currently available identifiers.
--
-- > percentFree s = numFree s / numAvailable s
-- > percentFree s + percentUsed s = 1
percentFree :: Statistics -> Double
percentFree s = fromIntegral (numFree s) / fromIntegral (numAvailable s)

-- | Percentage of identifiers currently in use.
--
-- > percentUsed s = numUsed s / numAvailable s
-- > percentUsed s + percentFree s = 1
percentUsed :: Statistics -> Double
percentUsed s = fromIntegral (numUsed s) / fromIntegral (numAvailable s)

-- | IdAllocator provides an interface for allocating and releasing
-- identifiers that correspond to server resources, such as node, buffer and
-- bus ids.
class IdAllocator a where
  -- | Id type allocated by this allocator.
  type Id a

  -- | Allocate a new identifier and return the changed allocator.
  alloc :: Failure AllocFailure m => a -> m (Id a, a)

  -- | Free a previously allocated identifier and return the changed allocator.
  --
  -- Freeing an identifier that hasn't been allocated with this allocator may
  -- trigger a failure.
  free  :: Failure AllocFailure m => Id a -> a -> m a

  -- | Return usage statistics.
  statistics :: a -> Statistics

-- | Allocate a number of (not necessarily consecutive) IDs with the given allocator.
--
-- Returns the list of IDs and the modified allocator.
allocMany :: (IdAllocator a, Failure AllocFailure m) => Int -> a -> m ([Id a], a)
allocMany n a = go n a []
  where
    go 0 a is = return (is, a)
    go !n !a is = do
      (i, a') <- alloc a
      go (n-1) a' (i:is)

-- | Free a number of IDs with the given allocator.
--
-- Returns the modified allocator.
freeMany :: (IdAllocator a, Failure AllocFailure m) => [Id a] -> a -> m a
freeMany is a = go is a
  where
    go [] a = return a
    go (i:is) a = free i a >>= go is

-- | RangeAllocator provides an interface for allocating and releasing ranges
--   of consecutive identifiers.
class IdAllocator a => RangeAllocator a where
  -- | Allocate n consecutive identifiers and return the changed allocator.
  allocRange :: Failure AllocFailure m => Int -> a -> m (Range (Id a), a)
  -- | Free a range of previously allocated identifiers and return the changed
  --   allocator.
  freeRange  :: Failure AllocFailure m => Range (Id a) -> a -> m a
