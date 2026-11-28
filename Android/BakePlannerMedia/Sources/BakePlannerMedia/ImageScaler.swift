// The whole file is the transpiled implementation; in the bridging build
// Skip generates the native side from it.
#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
#endif

/// Makes a photo small without first decoding it whole. `UIImage(data:)`
/// decodes a 50-megapixel camera JPEG into a 200 MB bitmap before anyone
/// can shrink it, which ends the app on a phone with little memory.
/// Here the picture's size is read first, then it is decoded already
/// reduced (`inSampleSize`), scaled to the edge wanted, turned the way
/// the camera says (EXIF) and written as JPEG. Both Android apps use it
/// through their PhotoShrinker.
public final class ImageScaler {

    /// `data` as a JPEG no longer than `longestEdge` pixels, at `quality`
    /// (0–100). A picture that is small enough already comes back as it
    /// is, unless `alwaysEncode` asks for a JPEG of it (a HEIC, say). Nil
    /// for data that is no picture.
    public static func jpeg(data: Data, longestEdge: Int, quality: Int, alwaysEncode: Bool) -> Data? {
        #if SKIP
        let bytes = data.platformValue
        let bounds = BitmapFactory.Options()
        bounds.inJustDecodeBounds = true
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        let width = bounds.outWidth
        let height = bounds.outHeight
        guard width > 0, height > 0 else { return nil }

        // How the camera held the phone: a JPEG carries it as EXIF, the
        // pixels themselves are not turned.
        var rotation = 0
        do {
            let exif = try ExifInterface(java.io.ByteArrayInputStream(bytes))
            let orientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            if orientation == ExifInterface.ORIENTATION_ROTATE_90 { rotation = 90 }
            if orientation == ExifInterface.ORIENTATION_ROTATE_180 { rotation = 180 }
            if orientation == ExifInterface.ORIENTATION_ROTATE_270 { rotation = 270 }
        } catch {
            rotation = 0
        }

        let longest = max(width, height)
        if longest <= longestEdge && rotation == 0 && !alwaysEncode {
            return data
        }

        // Decode at the largest power-of-two reduction that still leaves
        // the edge wanted, then scale the rest.
        var sample = 1
        while longest / (sample * 2) >= longestEdge {
            sample *= 2
        }
        let options = BitmapFactory.Options()
        options.inSampleSize = sample
        guard var bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) else { return nil }
        let decodedLongest = max(bitmap.width, bitmap.height)
        if decodedLongest > longestEdge {
            let factor = Double(longestEdge) / Double(decodedLongest)
            let newWidth = max(1, Int((Double(bitmap.width) * factor).rounded()))
            let newHeight = max(1, Int((Double(bitmap.height) * factor).rounded()))
            let scaled = Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
            if scaled !== bitmap { bitmap.recycle() }
            bitmap = scaled
        }
        if rotation != 0 {
            let matrix = Matrix()
            matrix.postRotate(Float(rotation))
            let turned = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            if turned !== bitmap { bitmap.recycle() }
            bitmap = turned
        }
        let out = java.io.ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, max(1, min(100, quality)), out)
        bitmap.recycle()
        return Data(platformValue: out.toByteArray())
        #else
        return nil
        #endif
    }
}
#endif
