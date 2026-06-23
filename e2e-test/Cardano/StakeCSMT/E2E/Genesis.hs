module Cardano.StakeCSMT.E2E.Genesis
    ( e2eGenesisStake
    , e2eGenesisStakingCredential
    , e2eGenesisStakingCredentialBytes
    , genesisDir
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
import Data.ByteString qualified as BS

genesisDir :: FilePath
genesisDir = "e2e-test/genesis"

e2eGenesisStakingCredential :: Credential Staking
e2eGenesisStakingCredential =
    case hashFromBytes e2eGenesisStakingCredentialBytes of
        Nothing -> error "invalid e2e genesis staking key hash bytes"
        Just keyHash -> KeyHashObj $ KeyHash keyHash

e2eGenesisStake :: Coin
e2eGenesisStake = Coin 30_000_000_000_000_000

e2eGenesisStakingCredentialBytes :: BS.ByteString
e2eGenesisStakingCredentialBytes =
    BS.pack
        [ 0x74
        , 0x1f
        , 0x46
        , 0x46
        , 0x5d
        , 0xa7
        , 0xe1
        , 0x7b
        , 0xe7
        , 0x94
        , 0xfd
        , 0xd6
        , 0x37
        , 0xa2
        , 0x7c
        , 0x0f
        , 0xc3
        , 0x81
        , 0x6f
        , 0x74
        , 0x81
        , 0x1d
        , 0x06
        , 0x01
        , 0x54
        , 0x3e
        , 0xdc
        , 0xfa
        ]
