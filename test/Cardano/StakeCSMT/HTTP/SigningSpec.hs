module Cardano.StakeCSMT.HTTP.SigningSpec
    ( spec
    ) where

import CSMT.Hashes
    ( Hash
    , renderHash
    )
import Cardano.Crypto.DSIGN.Class
    ( SignKeyDSIGN
    , genKeyDSIGN
    )
import Cardano.Crypto.DSIGN.Ed25519
    ( Ed25519DSIGN
    )
import Cardano.Crypto.Seed
    ( mkSeedFromBytes
    )
import Cardano.Ledger.Coin
    ( Coin (..)
    )
import Cardano.Slotting.Slot
    ( EpochNo (..)
    )
import Cardano.StakeCSMT.CSMT.Codecs
    ( coinCodec
    , csmtHashCodec
    , epochNoCodec
    )
import Cardano.StakeCSMT.HTTP.API
    ( LatestHeaderResponse (..)
    , renderHashBase16
    )
import Cardano.StakeCSMT.HTTP.Signing
    ( latestHeaderPayload
    , signLatestHeader
    , verifyLatestHeader
    )
import Control.Lens
    ( preview
    , review
    )
import Data.ByteString qualified as BS
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

spec :: Spec
spec =
    describe "HTTP.Signing" $ do
        it "serializes the latest-header payload deterministically" $ do
            latestHeaderPayload epoch42 root42 totalStake42
                `shouldBe` mconcat
                    [ review epochNoCodec epoch42
                    , renderHash root42
                    , review coinCodec totalStake42
                    ]

        it "verifies the exact signed latest-header payload" $ do
            let header =
                    signLatestHeader signingKey epoch42 root42 totalStake42

            verifyLatestHeader header `shouldBe` True

        it "rejects signatures when epoch, root, or total stake changes" $ do
            let header =
                    signLatestHeader signingKey epoch42 root42 totalStake42

            verifyLatestHeader header{epoch = EpochNo 43}
                `shouldBe` False
            verifyLatestHeader
                header{stakeRoot = renderHashBase16 $ testHash 99}
                `shouldBe` False
            verifyLatestHeader header{totalStake = Coin 61}
                `shouldBe` False

signingKey :: SignKeyDSIGN Ed25519DSIGN
signingKey =
    genKeyDSIGN @Ed25519DSIGN $ mkSeedFromBytes $ BS.replicate 32 11

epoch42 :: EpochNo
epoch42 = EpochNo 42

root42 :: Hash
root42 = testHash 42

totalStake42 :: Coin
totalStake42 = Coin 60

testHash :: Word -> Hash
testHash byte =
    case preview csmtHashCodec $ BS.replicate 32 $ fromIntegral byte of
        Nothing -> error "invalid deterministic CSMT hash bytes"
        Just hash -> hash
