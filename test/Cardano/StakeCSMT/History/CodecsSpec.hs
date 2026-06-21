module Cardano.StakeCSMT.History.CodecsSpec
    ( spec
    ) where

import Cardano.Ledger.Coin
    ( Coin (..)
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( EpochRoot (..)
    , Hash
    , csmtHashCodec
    )
import Cardano.StakeCSMT.History.Codecs
    ( historyLeafHash
    , historyPrefix
    , historyRootKeyCodec
    )
import Cardano.StakeCSMT.History.Columns qualified as HistoryColumns
import Control.Lens
    ( Prism'
    , preview
    , review
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
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    , shouldNotBe
    , shouldSatisfy
    )

spec :: Spec
spec =
    describe "History.Codecs" $ do
        it "builds a deterministic non-empty history prefix" $ do
            historyPrefix `shouldBe` historyPrefix
            historyPrefix `shouldSatisfy` (not . null)

        it "round-trips only the singleton history root key" $ do
            roundTrip historyRootKeyCodec ()
            preview historyRootKeyCodec "not-the-root"
                `shouldBe` Nothing

        it "changes the history leaf hash when total stake changes" $ do
            historyLeafHash rootA
                `shouldNotBe` historyLeafHash rootAWithDifferentStake

        it "changes the history leaf hash when the epoch root hash changes"
            $ historyLeafHash rootA
            `shouldNotBe` historyLeafHash rootB

        it "constructs an in-memory database with typed history columns" $ do
            _ <-
                mkInMemoryDatabase
                    $ mkColumns [0 :: Int ..] HistoryColumns.codecs
                    :: IO
                        ( Database
                            IO
                            Int
                            HistoryColumns.Columns
                            (Int, ByteString, Maybe ByteString)
                        )
            pure ()

roundTrip
    :: (Eq a, Show a)
    => Prism' ByteString a
    -> a
    -> IO ()
roundTrip codec value =
    preview codec (review codec value) `shouldBe` Just value

rootA :: EpochRoot
rootA =
    EpochRoot
        { epochRootHash = testHash 7
        , epochRootTotalStake = Coin 42
        }

rootAWithDifferentStake :: EpochRoot
rootAWithDifferentStake =
    rootA{epochRootTotalStake = Coin 43}

rootB :: EpochRoot
rootB =
    rootA{epochRootHash = testHash 8}

testHash :: Word -> Hash
testHash byte =
    case preview csmtHashCodec $ BS.replicate 32 $ fromIntegral byte of
        Nothing -> error "invalid deterministic CSMT hash bytes"
        Just hash -> hash
