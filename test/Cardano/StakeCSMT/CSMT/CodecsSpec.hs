module Cardano.StakeCSMT.CSMT.CodecsSpec
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
import Cardano.StakeCSMT.CSMT.Codecs
    ( Direction (..)
    , EpochRoot (..)
    , Hash
    , Indirect (..)
    , coinCodec
    , credentialCodec
    , csmtHashCodec
    , csmtIndirectHashCodec
    , csmtKeyCodec
    , epochPrefix
    , epochRootCodec
    )
import Control.Lens
    ( Prism'
    , preview
    , review
    )
import Data.ByteString
    ( ByteString
    )
import Data.ByteString qualified as BS
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    , shouldNotBe
    )

spec :: Spec
spec =
    describe "CSMT.Codecs" $ do
        it "round-trips Coin values through ledger CBOR" $ do
            roundTrip coinCodec (Coin 42)
            roundTrip coinCodec (Coin 1_000_000)

        it "round-trips deterministic staking credentials through ledger CBOR"
            $ roundTrip credentialCodec testCredential

        it "builds deterministic distinct epoch prefixes" $ do
            epochPrefix (EpochNo 37) `shouldBe` epochPrefix (EpochNo 37)
            epochPrefix (EpochNo 37) `shouldNotBe` epochPrefix (EpochNo 38)

        it "round-trips CSMT keys through CBOR"
            $ roundTrip csmtKeyCodec [L, R, R, L, L, R]

        it "round-trips indirect CSMT hashes through CBOR"
            $ roundTrip
                csmtIndirectHashCodec
                Indirect
                    { jump = [R, L, R]
                    , value = testHash
                    }

        it "round-trips epoch roots and preserves total stake" $ do
            let root =
                    EpochRoot
                        { epochRootHash = testHash
                        , epochRootTotalStake = Coin 12_345
                        }

            preview epochRootCodec (review epochRootCodec root)
                `shouldBe` Just root
            fmap
                epochRootTotalStake
                (preview epochRootCodec $ review epochRootCodec root)
                `shouldBe` Just (Coin 12_345)

roundTrip
    :: (Eq a, Show a)
    => Prism' ByteString a
    -> a
    -> IO ()
roundTrip codec value =
    preview codec (review codec value) `shouldBe` Just value

testCredential :: Credential Staking
testCredential =
    case hashFromBytes $ BS.replicate 28 7 of
        Nothing -> error "invalid deterministic key hash bytes"
        Just keyHash -> KeyHashObj $ KeyHash keyHash

testHash :: Hash
testHash = case preview csmtHashCodec $ BS.pack [0 .. 31] of
    Nothing -> error "invalid deterministic CSMT hash bytes"
    Just hash -> hash
