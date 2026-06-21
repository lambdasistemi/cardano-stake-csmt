{- |
Module      : Cardano.StakeCSMT.History.Columns
Description : Database column schema for history accumulator storage.

Column descriptors and codecs for epoch-root leaves, history tree nodes, and
the current history root.
-}
module Cardano.StakeCSMT.History.Columns
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
import Cardano.Slotting.Slot
    ( EpochNo
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( EpochRoot
    , csmtIndirectHashCodec
    , csmtKeyCodec
    , epochNoCodec
    , epochRootCodec
    )
import Cardano.StakeCSMT.History.Codecs
    ( historyRootKeyCodec
    , historyRootValueCodec
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

-- | History accumulator storage columns.
data Columns x where
    HistoryLeafCol :: Columns (KV EpochNo EpochRoot)
    HistoryTreeCol :: Columns (KV Key (Indirect Hash))
    HistoryRootCol :: Columns (KV () Hash)

instance GEq Columns where
    geq HistoryLeafCol HistoryLeafCol = Just Refl
    geq HistoryTreeCol HistoryTreeCol = Just Refl
    geq HistoryRootCol HistoryRootCol = Just Refl
    geq _ _ = Nothing

instance GCompare Columns where
    gcompare HistoryLeafCol HistoryLeafCol = GEQ
    gcompare HistoryLeafCol _ = GLT
    gcompare HistoryTreeCol HistoryLeafCol = GGT
    gcompare HistoryTreeCol HistoryTreeCol = GEQ
    gcompare HistoryTreeCol HistoryRootCol = GLT
    gcompare HistoryRootCol HistoryRootCol = GEQ
    gcompare HistoryRootCol _ = GGT

-- | Codecs for all history accumulator columns.
codecs :: DMap Columns Codecs
codecs =
    fromList
        [ HistoryLeafCol
            :=> Codecs
                { keyCodec = epochNoCodec
                , valueCodec = epochRootCodec
                }
        , HistoryTreeCol
            :=> Codecs
                { keyCodec = csmtKeyCodec
                , valueCodec = csmtIndirectHashCodec
                }
        , HistoryRootCol
            :=> Codecs
                { keyCodec = historyRootKeyCodec
                , valueCodec = historyRootValueCodec
                }
        ]
