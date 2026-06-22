module Cardano.StakeCSMT.HTTP.QuerySpec
    ( spec
    ) where

import CSMT.Hashes
    ( verifyInclusionProof
    )
import Cardano.Crypto.DSIGN.Class
    ( SignKeyDSIGN
    , genKeyDSIGN
    )
import Cardano.Crypto.DSIGN.Ed25519
    ( Ed25519DSIGN
    )
import Cardano.Crypto.Hash.Class
    ( hashFromBytes
    )
import Cardano.Crypto.Seed
    ( mkSeedFromBytes
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
    ( buildEpochCSMT
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( EpochRoot (..)
    , Hash
    , csmtHashCodec
    )
import Cardano.StakeCSMT.CSMT.Columns qualified as Stake
import Cardano.StakeCSMT.HTTP.API
    ( HistoryRootResponse (..)
    , LatestHeaderResponse (..)
    , StakeProofResponse (..)
    , StakeRootResponse (..)
    , renderCredentialBase16
    , renderHashBase16
    )
import Cardano.StakeCSMT.HTTP.Base16
    ( unsafeDecodeBase16Text
    )
import Cardano.StakeCSMT.HTTP.Query
    ( queryCurrentHistoryRoot
    , queryEpochRoots
    , queryHistoricalProof
    , queryLatestProof
    , querySignedLatestHeader
    )
import Cardano.StakeCSMT.HTTP.Signing
    ( verifyLatestHeader
    )
import Cardano.StakeCSMT.History.Builder
    ( finalizeEpochRoot
    )
import Cardano.StakeCSMT.History.Columns qualified as History
import Cardano.StakeCSMT.Ledger.StakeSnapshot
    ( StakeSnapshot (..)
    )
import Control.Lens
    ( preview
    )
import Control.Monad
    ( void
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
    describe "HTTP.Query" $ do
        it "returns historical proof bytes that verify against the stake root"
            $ do
                db <- freshStakeDb
                runTransactionUnguarded db
                    $ void
                    $ buildEpochCSMT epoch42 snapshot42

                mProof <-
                    runTransactionUnguarded db
                        $ queryHistoricalProof epoch42 credentialA

                case mProof of
                    Nothing ->
                        fail "expected a historical proof for credentialA"
                    Just StakeProofResponse{..} -> do
                        epoch `shouldBe` epoch42
                        credential
                            `shouldBe` renderCredentialBase16 credentialA
                        stake `shouldBe` Coin 10
                        totalStake `shouldBe` Coin 60
                        verifyInclusionProof
                            (unsafeDecodeBase16Text stakeRoot)
                            (unsafeDecodeBase16Text proofBytes)
                            `shouldBe` True

        it "chooses the newest epoch root for latest proof queries" $ do
            db <- freshStakeDb
            runTransactionUnguarded db $ do
                void $ buildEpochCSMT (EpochNo 41) snapshot41
                void $ buildEpochCSMT (EpochNo 43) snapshot43
                void $ buildEpochCSMT epoch42 snapshot42

            mProof <-
                runTransactionUnguarded db
                    $ queryLatestProof credentialA

            case mProof of
                Nothing ->
                    fail "expected a latest proof for credentialA"
                Just StakeProofResponse{epoch, stake} -> do
                    epoch `shouldBe` EpochNo 43
                    stake `shouldBe` Coin 99

        it "returns all persisted epoch roots sorted by epoch" $ do
            db <- freshStakeDb
            runTransactionUnguarded db $ do
                void $ buildEpochCSMT (EpochNo 43) snapshot43
                void $ buildEpochCSMT (EpochNo 41) snapshot41
                void $ buildEpochCSMT epoch42 snapshot42

            roots <- runTransactionUnguarded db queryEpochRoots

            fmap (\StakeRootResponse{epoch} -> epoch) roots
                `shouldBe` [EpochNo 41, epoch42, EpochNo 43]

        it "signs the newest epoch root for latest header queries" $ do
            db <- freshStakeDb
            runTransactionUnguarded db $ do
                void $ buildEpochCSMT (EpochNo 41) snapshot41
                void $ buildEpochCSMT (EpochNo 43) snapshot43
                void $ buildEpochCSMT epoch42 snapshot42

            mHeader <-
                runTransactionUnguarded db
                    $ querySignedLatestHeader signingKey

            case mHeader of
                Nothing ->
                    fail "expected a signed latest header"
                Just header@LatestHeaderResponse{epoch, totalStake} -> do
                    epoch `shouldBe` EpochNo 43
                    totalStake `shouldBe` Coin 200
                    verifyLatestHeader header `shouldBe` True

        it "returns the current history root" $ do
            db <- freshHistoryDb
            historyRoot <-
                runTransactionUnguarded db
                    $ finalizeEpochRoot epoch42 root42

            response <- runTransactionUnguarded db queryCurrentHistoryRoot

            response
                `shouldBe` Just
                    HistoryRootResponse
                        { historyRoot = renderHashBase16 historyRoot
                        }

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

epoch42 :: EpochNo
epoch42 = EpochNo 42

snapshot41 :: StakeSnapshot
snapshot41 =
    StakeSnapshot
        { stakeSnapshotStake =
            Map.fromList
                [ (credentialA, Coin 1)
                , (credentialB, Coin 2)
                ]
        , stakeSnapshotTotalStake = Coin 3
        }

snapshot42 :: StakeSnapshot
snapshot42 =
    StakeSnapshot
        { stakeSnapshotStake =
            Map.fromList
                [ (credentialA, Coin 10)
                , (credentialB, Coin 20)
                , (credentialC, Coin 30)
                ]
        , stakeSnapshotTotalStake = Coin 60
        }

snapshot43 :: StakeSnapshot
snapshot43 =
    StakeSnapshot
        { stakeSnapshotStake =
            Map.fromList
                [ (credentialA, Coin 99)
                , (credentialB, Coin 101)
                ]
        , stakeSnapshotTotalStake = Coin 200
        }

root42 :: EpochRoot
root42 =
    EpochRoot
        { epochRootHash = testHash 42
        , epochRootTotalStake = Coin 60
        }

credentialA :: Credential Staking
credentialA = testCredential 7

credentialB :: Credential Staking
credentialB = testCredential 8

credentialC :: Credential Staking
credentialC = testCredential 9

signingKey :: SignKeyDSIGN Ed25519DSIGN
signingKey =
    genKeyDSIGN @Ed25519DSIGN $ mkSeedFromBytes $ BS.replicate 32 11

testCredential :: Word -> Credential Staking
testCredential byte =
    case hashFromBytes $ BS.replicate 28 $ fromIntegral byte of
        Nothing -> error "invalid deterministic key hash bytes"
        Just keyHash -> KeyHashObj $ KeyHash keyHash

testHash :: Word -> Hash
testHash byte =
    case preview csmtHashCodec $ BS.replicate 32 $ fromIntegral byte of
        Nothing -> error "invalid deterministic CSMT hash bytes"
        Just hash -> hash
