{- |
Module      : Cardano.StakeCSMT.CSMT.Columns
Description : Database column schema for stake CSMT storage.

Column descriptors and codecs for stake snapshots, CSMT nodes, and epoch roots.
-}
module Cardano.StakeCSMT.CSMT.Columns
    ( Columns (..)
    , codecs
    )
where

import CSMT.Hashes
    ( Hash
    )
import CSMT.Interface
    ( Indirect
    , Key
    )
import Cardano.Ledger.Coin
    ( Coin
    )
import Cardano.Ledger.Credential
    ( Credential
    )
import Cardano.Ledger.Keys
    ( KeyRole (Staking)
    )
import Cardano.Slotting.Slot
    ( EpochNo
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( EpochRoot
    , coinCodec
    , csmtIndirectHashCodec
    , csmtKeyCodec
    , epochNoCodec
    , epochRootCodec
    , snapshotKeyCodec
    )
import Data.Type.Equality
    ( type (:~:) (Refl)
    )
import Database.KV.Transaction
    ( Codecs (..)
    , DMap
    , DSum ((:=>))
    , GCompare (..)
    , GEq (..)
    , GOrdering (..)
    , KV
    , fromList
    )

-- | Stake CSMT storage columns.
data Columns x where
    SnapshotCol :: Columns (KV (EpochNo, Credential Staking) Coin)
    TreeCol :: Columns (KV Key (Indirect Hash))
    RootCol :: Columns (KV EpochNo EpochRoot)

instance GEq Columns where
    geq SnapshotCol SnapshotCol = Just Refl
    geq TreeCol TreeCol = Just Refl
    geq RootCol RootCol = Just Refl
    geq _ _ = Nothing

instance GCompare Columns where
    gcompare SnapshotCol SnapshotCol = GEQ
    gcompare SnapshotCol _ = GLT
    gcompare TreeCol SnapshotCol = GGT
    gcompare TreeCol TreeCol = GEQ
    gcompare TreeCol RootCol = GLT
    gcompare RootCol RootCol = GEQ
    gcompare RootCol _ = GGT

-- | Codecs for all stake CSMT columns.
codecs :: DMap Columns Codecs
codecs =
    fromList
        [ SnapshotCol
            :=> Codecs
                { keyCodec = snapshotKeyCodec
                , valueCodec = coinCodec
                }
        , TreeCol
            :=> Codecs
                { keyCodec = csmtKeyCodec
                , valueCodec = csmtIndirectHashCodec
                }
        , RootCol
            :=> Codecs
                { keyCodec = epochNoCodec
                , valueCodec = epochRootCodec
                }
        ]
