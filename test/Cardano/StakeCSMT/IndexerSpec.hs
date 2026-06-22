module Cardano.StakeCSMT.IndexerSpec
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
    , queryEpochRoot
    , verifyCredentialProof
    )
import Cardano.StakeCSMT.CSMT.Columns qualified as Stake
import Cardano.StakeCSMT.History.Builder
    ( buildEpochRootProof
    , queryHistoryRoot
    , verifyEpochRootProof
    )
import Cardano.StakeCSMT.History.Columns qualified as History
import Cardano.StakeCSMT.Indexer
    ( IndexedEpoch (..)
    , indexStakeSnapshot
    )
import Cardano.StakeCSMT.Ledger.StakeSnapshot
    ( StakeSnapshot (..)
    )
import Data.ByteString
    ( ByteString
    )
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Database.KV.Database
    ( Database
    , mkColumns
    )
import Database.KV.InMemory
    ( mkInMemoryDatabase
    )
import Database.KV.Transaction
    ( runTransactionUnguarded
    )
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

spec :: Spec
spec =
    describe "Indexer" $ do
        it "writes a non-empty snapshot to stake and history stores" $ do
            stakeDb <- freshStakeDb
            historyDb <- freshHistoryDb

            result <-
                indexStakeSnapshot
                    stakeDb
                    historyDb
                    testEpoch
                    nonEmptySnapshot

            case result of
                Nothing ->
                    fail "expected a non-empty snapshot to be indexed"
                Just IndexedEpoch{..} -> do
                    indexedEpoch `shouldBe` testEpoch

                    storedEpochRoot <-
                        runTransactionUnguarded stakeDb
                            $ queryEpochRoot testEpoch
                    currentHistoryRoot <-
                        runTransactionUnguarded historyDb queryHistoryRoot

                    storedEpochRoot `shouldBe` Just indexedEpochRoot
                    currentHistoryRoot `shouldBe` Just indexedHistoryRoot

                    proofResult <-
                        runTransactionUnguarded stakeDb
                            $ buildCredentialProof testEpoch credentialA
                    case proofResult of
                        Nothing ->
                            fail "expected an inclusion proof for credentialA"
                        Just (coin, proof) -> do
                            coin `shouldBe` Coin 10
                            verifyCredentialProof
                                indexedEpochRoot
                                credentialA
                                coin
                                proof
                                `shouldBe` True

                    historyProofResult <-
                        runTransactionUnguarded historyDb
                            $ buildEpochRootProof testEpoch
                    case historyProofResult of
                        Nothing ->
                            fail "expected an epoch-root inclusion proof"
                        Just (storedRoot, proof) -> do
                            storedRoot `shouldBe` indexedEpochRoot
                            verifyEpochRootProof
                                indexedHistoryRoot
                                testEpoch
                                indexedEpochRoot
                                proof
                                `shouldBe` True

        it "does not write history when the snapshot is empty" $ do
            stakeDb <- freshStakeDb
            historyDb <- freshHistoryDb

            result <-
                indexStakeSnapshot
                    stakeDb
                    historyDb
                    testEpoch
                    emptySnapshot
            storedEpochRoot <-
                runTransactionUnguarded stakeDb
                    $ queryEpochRoot testEpoch
            currentHistoryRoot <-
                runTransactionUnguarded historyDb queryHistoryRoot

            result `shouldBe` Nothing
            storedEpochRoot `shouldBe` Nothing
            currentHistoryRoot `shouldBe` Nothing

freshStakeDb
    :: IO
        ( Database
            IO
            Int
            Stake.Columns
            (Int, ByteString, Maybe ByteString)
        )
freshStakeDb =
    mkInMemoryDatabase $ mkColumns [0 :: Int ..] Stake.codecs

freshHistoryDb
    :: IO
        ( Database
            IO
            Int
            History.Columns
            (Int, ByteString, Maybe ByteString)
        )
freshHistoryDb =
    mkInMemoryDatabase $ mkColumns [0 :: Int ..] History.codecs

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

emptySnapshot :: StakeSnapshot
emptySnapshot =
    StakeSnapshot
        { stakeSnapshotStake = Map.empty
        , stakeSnapshotTotalStake = Coin 0
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
