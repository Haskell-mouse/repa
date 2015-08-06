{-# LANGUAGE UndecidableInstances #-}
module Data.Repa.Convert.Format.Object
        ( Object        (..)
        , ObjectFormat  (..)
        , ObjectFields  (..)
        , mkObject)
where
import Data.Repa.Convert.Internal.Format
import Data.Repa.Convert.Internal.Packable
import Data.Repa.Convert.Internal.Packer
import Data.Repa.Convert.Format.String
import Data.Repa.Convert.Format.Binary
import Data.Repa.Scalar.Product
import Data.Monoid
import Data.Word
import Data.Char
import GHC.Exts
import Data.Text                        (Text)
import qualified Data.Text              as T


-- | Format of a simple object format with labeled fields.
data Object fields where
        Object
         :: ObjectFields fields
         -> Object fields


-- | Resents the fields of a JSON object.
data ObjectFields fields where

        ObjectFieldsNil  
         :: ObjectFields ()

        ObjectFieldsCons 
         :: {-# UNPACK #-} !ObjectMeta  -- Meta data about this format.
         -> !Text                       -- Name of head field
         -> !f                          -- Format of head field.
         -> ObjectFields fs             -- Spec for rest of fields.
         -> ObjectFields (f :*: fs)             


-- | Precomputed information about this format.
data ObjectMeta
        = ObjectMeta
        { -- | Length of this format, in fields.
          omFieldCount          :: !Int

          -- | Minimum length of this format, in bytes.
        , omMinSize             :: !Int

          -- | Fixed size of this format.
        , omFixedSize           :: !(Maybe Int) }


---------------------------------------------------------------------------------------------------
-- | Make an object format with the given labeled fields. For example:
--
-- @> let fmt = mkObject (("index", IntAsc) :*: ("message" :*: VarCharString \'-\') :*: ()))@
--
-- Packing this produces:
--
-- @
-- > let Just str = packToString fmt (27 :*: "foo" :*: ())
-- > putStrLn str
-- > {"value":27,"date":"foo"}
-- @ 
--
-- Note that the encodings that this format can generate are a superset of
-- the JavaScript Object Notation (JSON). With the Repa format, the fields
-- of an object can directly encode dates and other values, wheras in JSON
-- these values must be represented by strings.
--
mkObject :: ObjectFormat f 
         => f -> Object (ObjectFormat' f)

mkObject f = Object (mkObjectFields f)


class ObjectFormat f where
 type ObjectFormat' f
 mkObjectFields :: f -> ObjectFields (ObjectFormat' f)


instance ObjectFormat () where
 type ObjectFormat' () = ()
 mkObjectFields ()     = ObjectFieldsNil
 {-# INLINE mkObjectFields #-}


instance ( Format f1
         , ObjectFormat fs)
      => ObjectFormat ((String, f1) :*: fs) where

 type ObjectFormat' ((String, f1) :*: fs) 
        = f1 :*: ObjectFormat' fs

 mkObjectFields ((label, f1) :*: fs) 
  = case mkObjectFields fs of
        ObjectFieldsNil
         -> ObjectFieldsCons
                (ObjectMeta 
                        { omFieldCount  = 1

                          -- Smallest JSON object looks like:
                          --   {"LABEL":VALUE}, so there are 5 extra characters.
                        , omMinSize     = 5 + length label + minSize f1

                        , omFixedSize   = fmap (+ (5 + length label)) $ fixedSize f1 })
                (T.pack label) f1 ObjectFieldsNil

        cc@(ObjectFieldsCons jm _ _ _)
         -> ObjectFieldsCons
                (ObjectMeta 
                        { omFieldCount  = 1 + omFieldCount jm

                          -- Adding a new field makes the object look like:
                          --   {"LABEL1":VALUE1,"LABEL2":VALUE2}, so there are 4 extra
                          --   characters for addiitonal field,  1x',' + 2x'"' + 1x':'
                        , omMinSize     = 4 + minSize f1 + omMinSize jm

                        , omFixedSize
                             = do s1    <- fixedSize f1
                                  ss    <- omFixedSize jm
                                  return $ s1 + 4 + ss })
                (T.pack label) f1 cc
 {-# INLINE mkObjectFields #-}


---------------------------------------------------------------------------------------------------
instance ( Format (ObjectFields fs)
         , Value  (ObjectFields fs) ~ Value fs)
      => Format (Object fs) where
 type Value (Object fs)   
        = Value fs

 fieldCount (Object _)   
  = 1
 {-# INLINE fieldCount #-}

 minSize    (Object fs)   
  = 2 + minSize fs
 {-# INLINE minSize #-}

 fixedSize  (Object fs)   
  = do  sz      <- fixedSize fs
        return  (2 + sz)
 {-# INLINE fixedSize #-}

 packedSize (Object fs) xs
  = do  ps      <- packedSize fs xs
        return  $ 2 + ps
 {-# INLINE packedSize #-}


---------------------------------------------------------------------------------------------------
instance Format (ObjectFields ()) where
 type Value (ObjectFields ())   = ()
 fieldCount ObjectFieldsNil     = 0
 minSize    ObjectFieldsNil     = 0
 fixedSize  ObjectFieldsNil     = return 0
 packedSize ObjectFieldsNil _   = return 0
 {-# INLINE fieldCount #-}
 {-# INLINE minSize    #-}
 {-# INLINE fixedSize  #-}
 {-# INLINE packedSize #-}


instance Packable (ObjectFields ()) where
 packer   _fmt _val dst _fails k
  = k dst
 {-# INLINE packer #-}

 unpacker _fmt start _end _stop _fail eat
  = eat start ()
 {-# INLINE unpacker #-}


instance ( Format f1, Format (ObjectFields fs)
         , Value  (ObjectFields fs)  ~ Value fs)
        => Format (ObjectFields (f1 :*: fs)) where

 type Value (ObjectFields (f1 :*: fs))
        = Value f1 :*: Value fs

 fieldCount (ObjectFieldsCons jm _l1 _f1 _jfs)
  = omFieldCount jm
 {-# INLINE fieldCount #-}

 minSize    (ObjectFieldsCons jm _l1 _f1 _jfs)
  = omMinSize jm
 {-# INLINE minSize #-}

 fixedSize  (ObjectFieldsCons jm _l1 _f1 _jfs)
  = omFixedSize jm
 {-# INLINE fixedSize #-}

 packedSize (ObjectFieldsCons _jm _l1 f1 jfs) (x1 :*: xs)
  = do  s1      <- packedSize f1  x1
        ss      <- packedSize jfs xs
        let sSep = zeroOrOne (fieldCount jfs)
        return  $ s1 + sSep * 4 + ss
 {-# INLINE packedSize #-}


---------------------------------------------------------------------------------------------------
instance ( Format   (Object f)
         , Value    (ObjectFields f) ~ Value f
         , Packable (ObjectFields f))
        => Packable (Object f) where
 
 pack (Object fs) xs
        =  pack Word8be (w8 $ ord '{')
        <> pack fs xs
        <> pack Word8be (w8 $ ord '}')
 {-# INLINE pack #-}

 packer f v
        = fromPacker $ pack f v
 {-# INLINE packer #-}


---------------------------------------------------------------------------------------------------
instance ( Packable f1
         , Value    (ObjectFields ()) ~ Value ())
        => Packable (ObjectFields (f1 :*: ())) where

 pack   (ObjectFieldsCons _jm l1 f1 _jfs) (x1 :*: _)
        =  pack VarCharString (T.unpack l1)
        <> pack Word8be (w8 $ ord ':')
        <> pack f1 x1
 {-# INLINE pack #-}

 packer f v
        = fromPacker $ pack f v
 {-# INLINE packer #-}

instance ( Packable f1
         , Packable (ObjectFields (f2 :*: fs))
         , Value    (ObjectFields (f2 :*: fs)) ~ Value (f2 :*: fs)
         , Value    (ObjectFields fs)          ~ Value fs)
        => Packable (ObjectFields (f1 :*: f2 :*: fs)) where

 pack (ObjectFieldsCons _jm l1 f1 jfs) (x1 :*: xs)
        =   pack VarCharString (T.unpack l1)
        <>  pack Word8be (w8 $ ord ':')
        <>  pack f1 x1
        <>  pack Word8be (w8 $ ord ',')
        <>  pack jfs xs
 {-# INLINE pack #-}

 packer f v
        = fromPacker $ pack f v
 {-# INLINE packer #-}


---------------------------------------------------------------------------------------------------
w8  :: Integral a => a -> Word8
w8 = fromIntegral
{-# INLINE w8  #-}


-- | Branchless equality used to avoid compile-time explosion in size of core code.
zeroOrOne :: Int -> Int
zeroOrOne (I# i) = I# (1# -# (0# ==# i))
{-# INLINE zeroOrOne #-}
