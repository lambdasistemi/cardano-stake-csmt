module Cardano.StakeCSMT.CSMT.RocksDBSpec
    ( spec
    ) where

import Cardano.Crypto.Hash.Class
    ( hashFromBytes
    )
import Cardano.Ledger.Coin
    ( Coin (..)
    )
import Cardano.Ledger.Credential
    ( Credential (KeyHashObj)
    )
import Cardano.Ledger.Keys
    ( KeyHash (..)
    , KeyRole (Staking)
    )
import Cardano.Slotting.Slot
    ( EpochNo (..)
    )
import Cardano.StakeCSMT.CSMT.Builder
    ( buildCredentialProof
    , buildEpochCSMT
    , queryEpochRoot
    , verifyCredentialProof
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( epochPrefix
    )
import Cardano.StakeCSMT.CSMT.Columns
    ( Columns (..)
    )
import Cardano.StakeCSMT.CSMT.RocksDB
    ( mkStakeCSMTDatabase
    , withStakeCSMTRocksDB
    )
import Cardano.StakeCSMT.Ledger.StakeSnapshot
    ( StakeSnapshot (..)
    )
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
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
    describe "CSMT.RocksDB"
        $ it "persists epoch roots and proofs across close/reopen"
        $ withSystemTempDirectory "stake-csmt-rocksdb"
        $ \dbDir -> do
            Just builtRoot <-
                withStakeCSMTRocksDB dbDir $ \rocksDB ->
                    runTransactionUnguarded
                        (mkStakeCSMTDatabase rocksDB)
                        $ buildEpochCSMT testEpoch nonEmptySnapshot

            ( queriedRoot
                , proofResult
                , persistedSnapshot
                , persistedTreeRoot
                , persistedRoot
                ) <-
                withStakeCSMTRocksDB dbDir $ \rocksDB ->
                    runTransactionUnguarded
                        (mkStakeCSMTDatabase rocksDB)
                        $ do
                            root <- queryEpochRoot testEpoch
                            proof <-
                                buildCredentialProof
                                    testEpoch
                                    credentialA
                            snapshot <-
                                query
                                    SnapshotCol
                                    (testEpoch, credentialA)
                            treeRoot <-
                                query
                                    TreeCol
                                    (epochPrefix testEpoch)
                            directRoot <- query RootCol testEpoch
                            pure
                                ( root
                                , proof
                                , snapshot
                                , treeRoot
                                , directRoot
                                )

            queriedRoot `shouldBe` Just builtRoot
            persistedRoot `shouldBe` Just builtRoot
            persistedSnapshot `shouldBe` Just (Coin 10)
            case persistedTreeRoot of
                Nothing -> fail "expected persisted CSMT tree root node"
                Just _ -> pure ()
            case proofResult of
                Nothing ->
                    fail
                        "expected an inclusion proof after reopening RocksDB"
                Just (coin, proof) -> do
                    coin `shouldBe` Coin 10
                    verifyCredentialProof
                        builtRoot
                        credentialA
                        coin
                        proof
                        `shouldBe` True

testEpoch :: EpochNo
testEpoch = EpochNo 42

nonEmptySnapshot :: StakeSnapshot
nonEmptySnapshot =
    StakeSnapshot
        { stakeSnapshotStake =
            Map.fromList
                [ (credentialA, Coin 10)
                , (credentialB, Coin 20)
                , (credentialC, Coin 30)
                ]
        , stakeSnapshotTotalStake = Coin 60
        }

credentialA :: Credential Staking
credentialA = testCredential 7

credentialB :: Credential Staking
credentialB = testCredential 8

credentialC :: Credential Staking
credentialC = testCredential 9

testCredential :: Word -> Credential Staking
testCredential byte =
    case hashFromBytes $ BS.replicate 28 $ fromIntegral byte of
        Nothing -> error "invalid deterministic key hash bytes"
        Just keyHash -> KeyHashObj $ KeyHash keyHash
