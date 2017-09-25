{-# OPTIONS_GHC -fno-warn-orphans #-}

{- |
Module      :  Servant.RawM.Internal.Servant.Docs

Copyright   :  Dennis Gosnell 2017
License     :  BSD3

Maintainer  :  Dennis Gosnell (cdep.illabout@gmail.com)
Stability   :  experimental
Portability :  unknown

This module exports 'HasDocs' instances for 'Throws' and 'Throwing'.
-}

module Servant.RawM.Internal.Servant.Docs where

import Data.Proxy (Proxy(Proxy))
import Data.ByteString.Lazy (ByteString)
import Data.Function ((&))
import Data.Monoid ((<>))
import Data.Text (Text)
import Network.HTTP.Media (MediaType)
import Servant.API (Verb, (:>))
import Servant.API.ContentTypes (AllMimeRender(allMimeRender))
import Servant.Docs
       (Action, API, DocOptions, Endpoint, HasDocs(docsFor),
        ToSample(toSamples))
import Servant.Docs.Internal (apiEndpoints, respBody, response)

import Servant.RawM.Internal.Envelope
       (Envelope, toErrEnvelope, toSuccEnvelope)
import Servant.RawM.Internal.Prism ((<>~))
import Servant.RawM.Internal.Servant.API
       (NoThrow, Throws, Throwing)
import Servant.RawM.Internal.Util (Snoc)

-- TODO: Make sure to also account for when headers are being used.

-- | Change a 'Throws' into 'Throwing'.
instance (HasDocs (Throwing '[e] :> api)) => HasDocs (Throws e :> api) where
  docsFor
    :: Proxy (Throws e :> api)
    -> (Endpoint, Action)
    -> DocOptions
    -> API
  docsFor Proxy = docsFor (Proxy :: Proxy (Throwing '[e] :> api))

-- | When @'Throwing' es@ comes before a 'Verb', generate the documentation for
-- the same 'Verb', but returning an @'Envelope' es@.  Also add documentation
-- for the potential @es@.
instance
       ( CreateRespBodiesFor es ctypes
       , HasDocs (Verb method status ctypes (Envelope es a))
       )
    => HasDocs (Throwing es :> Verb method status ctypes a) where
  docsFor
    :: Proxy (Throwing es :> Verb method status ctypes a)
    -> (Endpoint, Action)
    -> DocOptions
    -> API
  docsFor Proxy (endpoint, action) docOpts =
    let api =
          docsFor
            (Proxy :: Proxy (Verb method status ctypes (Envelope es a)))
            (endpoint, action)
            docOpts
    in api & apiEndpoints . traverse . response . respBody <>~
        createRespBodiesFor (Proxy :: Proxy es) (Proxy :: Proxy ctypes)

-- | When 'NoThrow' comes before a 'Verb', generate the documentation for
-- the same 'Verb', but returning an @'Envelope' \'[]@.
instance (HasDocs (Verb method status ctypes (Envelope '[] a)))
    => HasDocs (NoThrow :> Verb method status ctypes a) where
  docsFor
    :: Proxy (NoThrow :> Verb method status ctypes a)
    -> (Endpoint, Action)
    -> DocOptions
    -> API
  docsFor Proxy (endpoint, action) docOpts =
    docsFor
      (Proxy :: Proxy (Verb method status ctypes (Envelope '[] a)))
      (endpoint, action)
      docOpts

-- | Create samples for a given @list@ of types, under given @ctypes@.
--
-- Additional instances of this class should not need to be created.
class CreateRespBodiesFor list ctypes where
  createRespBodiesFor
    :: Proxy list
    -> Proxy ctypes
    -> [(Text, MediaType, ByteString)]

-- | An empty list of types has no samples.
instance CreateRespBodiesFor '[] ctypes where
  createRespBodiesFor
    :: Proxy '[]
    -> Proxy ctypes
    -> [(Text, MediaType, ByteString)]
  createRespBodiesFor Proxy Proxy = []

-- | Create a response body for each of the error types.
instance
       ( AllMimeRender ctypes (Envelope '[e] ())
       , CreateRespBodiesFor es ctypes
       , ToSample e
       )
    => CreateRespBodiesFor (e ': es) ctypes where
  createRespBodiesFor
    :: Proxy (e ': es)
    -> Proxy ctypes
    -> [(Text, MediaType, ByteString)]
  createRespBodiesFor Proxy ctypes =
    createRespBodyFor (Proxy :: Proxy e) ctypes <>
    createRespBodiesFor (Proxy :: Proxy es) ctypes

-- | Create a sample for a given @e@ under given @ctypes@.
createRespBodyFor
  :: forall e ctypes.
     (AllMimeRender ctypes (Envelope '[e] ()), ToSample e)
  => Proxy e -> Proxy ctypes -> [(Text, MediaType, ByteString)]
createRespBodyFor Proxy ctypes = concatMap enc samples
    where
      samples :: [(Text, Envelope '[e] ())]
      samples = fmap toErrEnvelope <$> toSamples (Proxy :: Proxy e)

      enc :: (Text, Envelope '[e] ()) -> [(Text, MediaType, ByteString)]
      enc (t, s) = uncurry (t,,) <$> allMimeRender ctypes s

-- | When a @'Throws' e@ comes immediately after a @'Throwing' es@, 'Snoc' the
-- @e@ onto the @es@.
instance (HasDocs (Throwing (Snoc es e) :> api)) =>
    HasDocs (Throwing es :> Throws e :> api) where
  docsFor
    :: Proxy (Throwing es :> Throws e :> api)
    -> (Endpoint, Action)
    -> DocOptions
    -> API
  docsFor Proxy =
    docsFor (Proxy :: Proxy (Throwing (Snoc es e) :> api))

-- | We can generate a sample of an @'Envelope' es a@ as long as there is a way
-- to generate a sample of the @a@.
--
-- This doesn't need to worry about generating a sample of @es@, because that is
-- taken care of in the 'HasDocs' instance for @'Throwing' es@.
instance ToSample a => ToSample (Envelope es a) where
  toSamples :: Proxy (Envelope es a) -> [(Text, Envelope es a)]
  toSamples Proxy = fmap toSuccEnvelope <$> toSamples (Proxy :: Proxy a)
