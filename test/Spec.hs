{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

module Main where

import Control.Exception (Exception, SomeException, catch)
import Data.Proxy (Proxy(Proxy))
import Data.Type.Equality ((:~:)(Refl))
import Data.Typeable (Typeable)
import Network.Wai (Application)
import Servant ((:<|>)((:<|>)), (:>), Capture, Get, Handler, JSON, ServerT, serve)
import Test.Hspec.Wai (get, shouldRespondWith, with)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.Hspec (describe, it, testSpec)
import Test.Tasty.HUnit ((@?=), assertFailure, testCase)

import Servant.Checked.Exceptions
       (Envelope, NoThrow, Throws, pureErrEnvelope, pureSuccEnvelope)

main :: IO ()
main = do
  tests <- testsIO
  defaultMain tests

testsIO :: IO TestTree
testsIO = do
  serverTests <- serverTestsIO
  pure $
    testGroup
      "tests"
      [ hasServerInstanceTests
      , serverTests
      ]

-------------
-- Helpers --
-------------

type Selector e = e -> Bool

anyException :: Selector SomeException
anyException _ = True

-- | Extra HUnit assertion to make sure an expression throws an exception.
assertThrows
  :: forall e a.
     (Exception e, Typeable e)
  => IO a -> Selector e -> IO ()
assertThrows ioAction selector = do
  didCatch <- catch (ioAction *> pure False) (pure . selector)
  case didCatch of
    False ->
      assertFailure "expecting an exception, but no exception occurred"
    True -> pure ()

-- | Infix version of 'assertThrows'.
(@!)
  :: (Exception e, Typeable e)
  => IO a -> Selector e -> IO ()
(@!) = assertThrows

infix 1 @!

------------------------------
-- HasServer instance tests --
------------------------------

type ApiThrows = Throws String :> Get '[JSON] Int

checkApiThrows :: ServerT ApiThrows m :~: m (Envelope '[String] Int)
checkApiThrows = Refl

type ApiDoubleThrows = Throws String :> Throws Double :> Get '[JSON] Int

checkApiDoubleThrows
  :: ServerT ApiDoubleThrows m :~: m (Envelope '[String, Double] Int)
checkApiDoubleThrows = Refl

type ApiThrowsBeforeCapture =
  Throws String :> Capture "foobar" Double :> Get '[JSON] Int

checkApiThrowsBeforeCapture
  :: ServerT ApiThrowsBeforeCapture m :~: (Double -> m (Envelope '[String] Int))
checkApiThrowsBeforeCapture = Refl

type ApiThrowsBeforeMulti =
  Throws String :> (Get '[JSON] Int :<|> Get '[JSON] Double)

checkApiThrowsBeforeMulti
  :: ServerT ApiThrowsBeforeMulti m :~:
     (m (Envelope '[String] Int) :<|> m (Envelope '[String] Double))
checkApiThrowsBeforeMulti = Refl

type ApiNoThrow = NoThrow :> Get '[JSON] Int

checkApiNoThrows :: ServerT ApiNoThrow m :~: m (Envelope '[] Int)
checkApiNoThrows = Refl

type ApiNoThrowBeforeCapture =
  NoThrow :> Capture "foobar" Double :> Get '[JSON] Int

checkApiNoThrowBeforeCapture
  :: ServerT ApiNoThrowBeforeCapture m :~: (Double -> m (Envelope '[] Int))
checkApiNoThrowBeforeCapture = Refl

type ApiNoThrowBeforeMulti =
  NoThrow :> (Get '[JSON] Int :<|> Get '[JSON] Double)

checkApiNoThrowBeforeMulti
  :: ServerT ApiNoThrowBeforeMulti m :~:
     (m (Envelope '[] Int) :<|> m (Envelope '[] Double))
checkApiNoThrowBeforeMulti = Refl

hasServerInstanceTests :: TestTree
hasServerInstanceTests =
  testGroup
    "HasServer instances"
    [ testCase "single Throws" $ checkApiThrows @?= Refl
    , testCase "double Throws" $ checkApiDoubleThrows @?= Refl
    , testCase "Throws before Capture" $ checkApiThrowsBeforeCapture @?= Refl
    , testCase "Throws before (:<|>)" $ checkApiThrowsBeforeMulti @?= Refl
    , testCase "single NoThrows" $ checkApiNoThrows @?= Refl
    , testCase "NoThrow before Capture" $ checkApiNoThrowBeforeCapture @?= Refl
    , testCase "NoThrow before (:<|>)" $ checkApiNoThrowBeforeMulti @?= Refl
    ]

------------------
-- Server tests --
------------------

type TestThrows = Capture "foobar" Double :> Throws Int :> Get '[JSON] String

type TestNoThrow = Capture "baz" Integer :> NoThrow :> Get '[JSON] String

type TestApi = TestThrows :<|> TestNoThrow

server :: ServerT TestApi Handler
server = testThrowsGet :<|> testNoThrowsGet

testThrowsGet :: Double -> Handler (Envelope '[Int] String)
testThrowsGet double =
  if double < 0
    then pureErrEnvelope (0 :: Int)
    else pureSuccEnvelope "success"

testNoThrowsGet :: Integer -> Handler (Envelope '[] String)
testNoThrowsGet _ = pureSuccEnvelope "success"

app :: Application
app = serve (Proxy :: Proxy TestApi) server

serverTestsIO :: IO TestTree
serverTestsIO =
  testSpec "server" $
    with (pure app) $ do
      describe "Throws" $ do
        it "handler can return error envelope" $
          get "/-5" `shouldRespondWith` "{\"err\":0}"
        it "handler can return success envelope" $
          get "/10" `shouldRespondWith` "{\"data\":\"success\"}"
      describe "NoThrow" $ do
        it "handler can return success envelope" $
          get "/10" `shouldRespondWith` "{\"data\":\"success\"}"
