{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}
module Sound.SC3.Server.Allocator.SimpleAllocator (
    SimpleAllocator
  , cons
) where

import           Control.Failure (Failure, failure)
import           Sound.SC3.Server.Allocator
import           Sound.SC3.Server.Allocator.Range (Range)
import qualified Sound.SC3.Server.Allocator.Range as Range

data SimpleAllocator i =
    SimpleAllocator
        {-# UNPACK #-}!(Range i)
        {-# UNPACK #-}!Int
                      !i
        deriving (Eq, Show)

cons :: Range i -> SimpleAllocator i
cons r = SimpleAllocator r 0 (Range.begin r)

_alloc :: (Enum i, Ord i, Monad m) => SimpleAllocator i -> m (i, SimpleAllocator i)
_alloc (SimpleAllocator r n i) =
    let i' = succ i
    in return (i, SimpleAllocator r (n+1) (if i' >= Range.end r then Range.begin r else i'))

_free :: (Failure AllocFailure m) => i -> SimpleAllocator i -> m (SimpleAllocator i)
_free _ (SimpleAllocator r n i) =
    let n' = n-1
    in if n' < 0
       then failure InvalidId
       else return (SimpleAllocator r n' i)

_statistics :: Integral i => SimpleAllocator i -> Statistics
_statistics (SimpleAllocator r n _) =
    let k = fromIntegral (Range.size r)
    in Statistics {
        numAvailable = k
      , numFree = k - n
      , numUsed = n }

instance (Integral i) => IdAllocator (SimpleAllocator i) where
    type Id (SimpleAllocator i) = i
    alloc                       = _alloc
    free                        = _free
    statistics                  = _statistics
