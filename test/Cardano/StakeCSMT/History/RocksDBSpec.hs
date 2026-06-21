module Cardano.StakeCSMT.History.RocksDBSpec
    ( spec
    ) where

import Cardano.Ledger.Coin
    ( Coin (..)
    )
import Cardano.Slotting.Slot
    ( EpochNo (..)
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( EpochRoot (..)
    , Hash
    , csmtHashCodec
    )
import Cardano.StakeCSMT.History.Builder
    ( buildEpochRootProof
    , finalizeEpochRoot
    , queryHistoryLeaf
    , queryHistoryRoot
    , verifyEpochRootProof
    )
import Cardano.StakeCSMT.History.Codecs
    ( historyPrefix
    )
import Cardano.StakeCSMT.History.Columns
    ( Columns (..)
    )
import Cardano.StakeCSMT.History.RocksDB
    ( mkHistoryDatabase
    , withHistoryRocksDB
    )
import Control.Lens
    ( preview
    )
import Data.ByteString qualified as BS
import Database.KV.Transaction
    ( query
    , runTransactionUnguarded
    )
import System.IO.Temp
    ( withSystemTempDirectory
    )
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

spec :: Spec
spec =
    describe "History.RocksDB"
        $ it
            "persists history roots, leaves, tree nodes, and proofs across close/reopen"
        $ withSystemTempDirectory "history-rocksdb"
        $ \dbDir -> do
            lastHistoryRoot <-
                withHistoryRocksDB dbDir $ \rocksDB ->
                    runTransactionUnguarded
                        (mkHistoryDatabase rocksDB)
                        $ do
                            _ <- finalizeEpochRoot firstEpoch firstEpochRoot
                            finalizeEpochRoot secondEpoch secondEpochRoot

            ( queriedRoot
                , queriedLeaf
                , persistedLeaf
                , persistedTreeRoot
                , persistedRoot
                , proofResult
                ) <-
                withHistoryRocksDB dbDir $ \rocksDB ->
                    runTransactionUnguarded
                        (mkHistoryDatabase rocksDB)
                        $ do
                            root <- queryHistoryRoot
                            leaf <- queryHistoryLeaf secondEpoch
                            directLeaf <- query HistoryLeafCol secondEpoch
                            treeRoot <- query HistoryTreeCol historyPrefix
                            directRoot <- query HistoryRootCol ()
                            proof <- buildEpochRootProof secondEpoch
                            pure
                                ( root
                                , leaf
                                , directLeaf
                                , treeRoot
                                , directRoot
                                , proof
                                )

            queriedRoot `shouldBe` Just lastHistoryRoot
            queriedLeaf `shouldBe` Just secondEpochRoot
            persistedLeaf `shouldBe` Just secondEpochRoot
            persistedRoot `shouldBe` Just lastHistoryRoot
            case persistedTreeRoot of
                Nothing -> fail "expected persisted history tree root node"
                Just _ -> pure ()
            case proofResult of
                Nothing ->
                    fail
                        "expected an epoch-root inclusion proof after reopening RocksDB"
                Just (storedRoot, proof) -> do
                    storedRoot `shouldBe` secondEpochRoot
                    verifyEpochRootProof
                        lastHistoryRoot
                        secondEpoch
                        secondEpochRoot
                        proof
                        `shouldBe` True

firstEpoch :: EpochNo
firstEpoch = EpochNo 42

secondEpoch :: EpochNo
secondEpoch = EpochNo 43

firstEpochRoot :: EpochRoot
firstEpochRoot =
    EpochRoot
        { epochRootHash = testHash 7
        , epochRootTotalStake = Coin 42
        }

secondEpochRoot :: EpochRoot
secondEpochRoot =
    EpochRoot
        { epochRootHash = testHash 11
        , epochRootTotalStake = Coin 99
        }

testHash :: Word -> Hash
testHash byte =
    case preview csmtHashCodec $ BS.replicate 32 $ fromIntegral byte of
        Nothing -> error "invalid deterministic CSMT hash bytes"
        Just hash -> hash
