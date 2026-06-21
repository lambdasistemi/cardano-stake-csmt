module Cardano.StakeCSMT.CSMT.BuilderSpec
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
import Cardano.StakeCSMT.CSMT.Columns
    ( Columns
    , codecs
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
    describe "CSMT.Builder" $ do
        it
            "builds deterministic epoch roots for identical non-empty snapshots"
            $ do
                db1 <- freshDb
                db2 <- freshDb

                root1 <-
                    runTransactionUnguarded db1
                        $ buildEpochCSMT testEpoch nonEmptySnapshot
                root2 <-
                    runTransactionUnguarded db2
                        $ buildEpochCSMT testEpoch nonEmptySnapshot

                root1 `shouldBe` root2

        it "queries the root inserted for an epoch" $ do
            db <- freshDb

            built <-
                runTransactionUnguarded db
                    $ buildEpochCSMT testEpoch nonEmptySnapshot
            queried <-
                runTransactionUnguarded db
                    $ queryEpochRoot testEpoch

            queried `shouldBe` built

        it "builds and verifies a credential inclusion proof" $ do
            db <- freshDb

            Just root <-
                runTransactionUnguarded db
                    $ buildEpochCSMT testEpoch nonEmptySnapshot
            proofResult <-
                runTransactionUnguarded db
                    $ buildCredentialProof testEpoch credentialA

            case proofResult of
                Nothing ->
                    fail "expected an inclusion proof for credentialA"
                Just (coin, proof) -> do
                    coin `shouldBe` Coin 10
                    verifyCredentialProof root credentialA coin proof
                        `shouldBe` True
                    verifyCredentialProof root credentialB coin proof
                        `shouldBe` False
                    verifyCredentialProof root credentialA (Coin 11) proof
                        `shouldBe` False

        it "rejects a proof checked against the wrong root" $ do
            db <- freshDb

            Just root <-
                runTransactionUnguarded db
                    $ buildEpochCSMT testEpoch nonEmptySnapshot
            Just wrongRoot <-
                runTransactionUnguarded db
                    $ buildEpochCSMT (EpochNo 43) differentSnapshot
            Just (coin, proof) <-
                runTransactionUnguarded db
                    $ buildCredentialProof testEpoch credentialA

            verifyCredentialProof root credentialA coin proof
                `shouldBe` True
            verifyCredentialProof wrongRoot credentialA coin proof
                `shouldBe` False

        it "returns Nothing for empty snapshots and missing roots" $ do
            db <- freshDb

            built <-
                runTransactionUnguarded db
                    $ buildEpochCSMT testEpoch emptySnapshot
            queried <-
                runTransactionUnguarded db
                    $ queryEpochRoot testEpoch

            built `shouldBe` Nothing
            queried `shouldBe` Nothing

freshDb
    :: IO (Database IO Int Columns (Int, ByteString, Maybe ByteString))
freshDb =
    mkInMemoryDatabase $ mkColumns [0 :: Int ..] codecs

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

differentSnapshot :: StakeSnapshot
differentSnapshot =
    StakeSnapshot
        { stakeSnapshotStake =
            Map.fromList
                [ (credentialA, Coin 10)
                , (credentialB, Coin 20)
                , (credentialC, Coin 31)
                ]
        , stakeSnapshotTotalStake = Coin 61
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
