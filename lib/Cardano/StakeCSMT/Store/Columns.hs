{-# LANGUAGE GADTs #-}

{- |
Module      : Cardano.StakeCSMT.Store.Columns
Description : Unified stake CSMT and history accumulator columns.

Column descriptors for the single physical store used by epoch indexing.
Typed projections keep stake and history query code working against their
domain-specific column GADTs.
-}
module Cardano.StakeCSMT.Store.Columns
    ( Columns (..)
    , codecs
    , historyDatabase
    , stakeDatabase
    )
where

import Cardano.StakeCSMT.CSMT.Columns qualified as Stake
import Cardano.StakeCSMT.History.Columns qualified as History
import Database.KV.Database
    ( Column
    , Database (..)
    , getColumn
    )
import Database.KV.Transaction
    ( Codecs
    , DMap
    , DSum ((:=>))
    , GCompare (..)
    , GEq (..)
    , GOrdering (..)
    , fromList
    )

-- | Columns for the unified RocksDB store.
data Columns c where
    StakeColumn :: Stake.Columns c -> Columns c
    HistoryColumn :: History.Columns c -> Columns c

instance GEq Columns where
    geq (StakeColumn left) (StakeColumn right) = geq left right
    geq (HistoryColumn left) (HistoryColumn right) = geq left right
    geq _ _ = Nothing

instance GCompare Columns where
    gcompare (StakeColumn left) (StakeColumn right) =
        gcompare left right
    gcompare (StakeColumn _) (HistoryColumn _) =
        GLT
    gcompare (HistoryColumn _) (StakeColumn _) =
        GGT
    gcompare (HistoryColumn left) (HistoryColumn right) =
        gcompare left right

-- | Codecs for every column in the unified store.
codecs :: DMap Columns Codecs
codecs =
    fromList
        [ StakeColumn Stake.SnapshotCol
            :=> stakeCodec Stake.SnapshotCol
        , StakeColumn Stake.TreeCol
            :=> stakeCodec Stake.TreeCol
        , StakeColumn Stake.RootCol
            :=> stakeCodec Stake.RootCol
        , HistoryColumn History.HistoryLeafCol
            :=> historyCodec History.HistoryLeafCol
        , HistoryColumn History.HistoryTreeCol
            :=> historyCodec History.HistoryTreeCol
        , HistoryColumn History.HistoryRootCol
            :=> historyCodec History.HistoryRootCol
        ]
  where
    stakeCodec selector =
        case getColumn selector Stake.codecs of
            Just codec -> codec
            Nothing -> error "Store.codecs: stake codec not found"

    historyCodec selector =
        case getColumn selector History.codecs of
            Just codec -> codec
            Nothing -> error "Store.codecs: history codec not found"

-- | Project the unified store to the stake CSMT database view.
stakeDatabase
    :: Database m cf Columns ops
    -> Database m cf Stake.Columns ops
stakeDatabase db@Database{columns = storeColumns} =
    Database
        { valueAt = valueAt db
        , applyOps = applyOps db
        , mkOperation = mkOperation db
        , newIterator = newIterator db
        , columns =
            fromList
                [ Stake.SnapshotCol
                    :=> expectStoreColumn
                        "stakeDatabase"
                        storeColumns
                        (StakeColumn Stake.SnapshotCol)
                , Stake.TreeCol
                    :=> expectStoreColumn
                        "stakeDatabase"
                        storeColumns
                        (StakeColumn Stake.TreeCol)
                , Stake.RootCol
                    :=> expectStoreColumn
                        "stakeDatabase"
                        storeColumns
                        (StakeColumn Stake.RootCol)
                ]
        , withSnapshot = \action ->
            withSnapshot db $ action . stakeDatabase
        }

-- | Project the unified store to the history accumulator database view.
historyDatabase
    :: Database m cf Columns ops
    -> Database m cf History.Columns ops
historyDatabase db@Database{columns = storeColumns} =
    Database
        { valueAt = valueAt db
        , applyOps = applyOps db
        , mkOperation = mkOperation db
        , newIterator = newIterator db
        , columns =
            fromList
                [ History.HistoryLeafCol
                    :=> expectStoreColumn
                        "historyDatabase"
                        storeColumns
                        (HistoryColumn History.HistoryLeafCol)
                , History.HistoryTreeCol
                    :=> expectStoreColumn
                        "historyDatabase"
                        storeColumns
                        (HistoryColumn History.HistoryTreeCol)
                , History.HistoryRootCol
                    :=> expectStoreColumn
                        "historyDatabase"
                        storeColumns
                        (HistoryColumn History.HistoryRootCol)
                ]
        , withSnapshot = \action ->
            withSnapshot db $ action . historyDatabase
        }

expectStoreColumn
    :: String
    -> DMap Columns (Column cf)
    -> Columns c
    -> Column cf c
expectStoreColumn label storeColumns selector =
    case getColumn selector storeColumns of
        Just column -> column
        Nothing -> error $ label <> ": column not found"
