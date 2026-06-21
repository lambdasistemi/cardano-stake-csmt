module Cardano.StakeCSMT.History.BuilderSpec
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
import Cardano.StakeCSMT.History.Columns
    ( Columns
    , codecs
    )
import Control.Lens
    ( preview
    )
import Data.ByteString
    ( ByteString
    )
import Data.ByteString qualified as BS
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
    describe "History.Builder" $ do
        it "returns Nothing for an empty history database" $ do
            db <- freshDb

            root <- runTransactionUnguarded db queryHistoryRoot
            leaf <-
                runTransactionUnguarded db
                    $ queryHistoryLeaf testEpoch
            proofResult <-
                runTransactionUnguarded db
                    $ buildEpochRootProof testEpoch

            root `shouldBe` Nothing
            leaf `shouldBe` Nothing
            proofResult `shouldBe` Nothing

        it "builds deterministic history roots for identical epochs" $ do
            db1 <- freshDb
            db2 <- freshDb

            result1 <- finalizeSequence db1
            result2 <- finalizeSequence db2

            result1 `shouldBe` result2

        it "stores finalized leaves and updates the current root" $ do
            db <- freshDb

            (root, leaf, currentRoot) <-
                runTransactionUnguarded db $ do
                    root <- finalizeEpochRoot testEpoch rootA
                    leaf <- queryHistoryLeaf testEpoch
                    currentRoot <- queryHistoryRoot
                    pure (root, leaf, currentRoot)

            leaf `shouldBe` Just rootA
            currentRoot `shouldBe` Just root

        it "builds and verifies an epoch-root inclusion proof" $ do
            db <- freshDb

            (historyRoot, proofResult) <-
                runTransactionUnguarded db $ do
                    historyRoot <- finalizeEpochRoot testEpoch rootA
                    proofResult <- buildEpochRootProof testEpoch
                    pure (historyRoot, proofResult)

            case proofResult of
                Nothing ->
                    fail "expected an epoch-root inclusion proof"
                Just (storedRoot, proof) -> do
                    storedRoot `shouldBe` rootA
                    verifyEpochRootProof
                        historyRoot
                        testEpoch
                        rootA
                        proof
                        `shouldBe` True

        it "rejects proofs for changed leaves and wrong roots" $ do
            db <- freshDb
            wrongDb <- freshDb

            (historyRoot, Just (storedRoot, proof)) <-
                runTransactionUnguarded db $ do
                    historyRoot <- finalizeEpochRoot testEpoch rootA
                    proofResult <- buildEpochRootProof testEpoch
                    pure (historyRoot, proofResult)
            wrongHistoryRoot <-
                runTransactionUnguarded wrongDb
                    $ finalizeEpochRoot otherEpoch rootB

            storedRoot `shouldBe` rootA
            verifyEpochRootProof historyRoot testEpoch rootA proof
                `shouldBe` True
            verifyEpochRootProof historyRoot otherEpoch rootA proof
                `shouldBe` False
            verifyEpochRootProof
                historyRoot
                testEpoch
                rootAWithDifferentHash
                proof
                `shouldBe` False
            verifyEpochRootProof
                historyRoot
                testEpoch
                rootAWithDifferentStake
                proof
                `shouldBe` False
            verifyEpochRootProof wrongHistoryRoot testEpoch rootA proof
                `shouldBe` False

freshDb
    :: IO (Database IO Int Columns (Int, ByteString, Maybe ByteString))
freshDb =
    mkInMemoryDatabase $ mkColumns [0 :: Int ..] codecs

finalizeSequence
    :: Database IO Int Columns (Int, ByteString, Maybe ByteString)
    -> IO ([Hash], Maybe Hash)
finalizeSequence db =
    runTransactionUnguarded db $ do
        roots <-
            traverse
                (uncurry finalizeEpochRoot)
                [ (EpochNo 40, rootC)
                , (testEpoch, rootA)
                , (otherEpoch, rootB)
                ]
        currentRoot <- queryHistoryRoot
        pure (roots, currentRoot)

testEpoch :: EpochNo
testEpoch = EpochNo 42

otherEpoch :: EpochNo
otherEpoch = EpochNo 43

rootA :: EpochRoot
rootA =
    EpochRoot
        { epochRootHash = testHash 7
        , epochRootTotalStake = Coin 42
        }

rootAWithDifferentHash :: EpochRoot
rootAWithDifferentHash =
    rootA{epochRootHash = testHash 8}

rootAWithDifferentStake :: EpochRoot
rootAWithDifferentStake =
    rootA{epochRootTotalStake = Coin 43}

rootB :: EpochRoot
rootB =
    EpochRoot
        { epochRootHash = testHash 11
        , epochRootTotalStake = Coin 99
        }

rootC :: EpochRoot
rootC =
    EpochRoot
        { epochRootHash = testHash 13
        , epochRootTotalStake = Coin 111
        }

testHash :: Word -> Hash
testHash byte =
    case preview csmtHashCodec $ BS.replicate 32 $ fromIntegral byte of
        Nothing -> error "invalid deterministic CSMT hash bytes"
        Just hash -> hash
