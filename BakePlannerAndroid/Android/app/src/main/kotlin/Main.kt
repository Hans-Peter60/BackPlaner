package bake.planner

import skip.lib.*
import skip.model.*
import skip.foundation.*
import skip.ui.*

import android.Manifest
import android.app.Application
import android.graphics.Color as AndroidColor
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.SystemBarStyle
import androidx.activity.ComponentActivity
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.core.app.ActivityCompat
import androidx.work.Configuration
import com.google.firebase.appcheck.FirebaseAppCheck
import com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory
import com.google.firebase.appcheck.playintegrity.PlayIntegrityAppCheckProviderFactory

internal val logger: SkipLogger = SkipLogger(subsystem = "bake.planner", category = "BakePlanner")

private typealias AppRootView = BakePlannerRootView
private typealias AppDelegate = BakePlannerAppDelegate

/// AndroidAppMain is the `android.app.Application` entry point, and must match `application android:name` in the AndroidMainfest.xml file.
open class AndroidAppMain: Application, Configuration.Provider {
    constructor() {
    }

    /// WorkManager starts with the app's reminder worker in place of
    /// SkipUI's (see Reminders.kt); the default initializer is removed in
    /// AndroidManifest.xml so that this configuration is used.
    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(ReminderWorkerFactory())
            .build()

    override fun onCreate() {
        super.onCreate()
        logger.info("starting app")
        ProcessInfo.launch(applicationContext)
        AppDelegate.shared.onInit()
        installAppCheck()
    }

    /// App Check proves to Firebase that requests come from the genuine
    /// app. A debug build uses the debug provider, whose token (printed to
    /// the log on the first start) is registered in the Firebase console;
    /// the store build uses Play Integrity, which Google Play vouches for.
    /// Installed once the app's Swift has configured Firebase (onInit).
    private fun installAppCheck() {
        val factory = if (BuildConfig.DEBUG) {
            DebugAppCheckProviderFactory.getInstance()
        } else {
            PlayIntegrityAppCheckProviderFactory.getInstance()
        }
        FirebaseAppCheck.getInstance().installAppCheckProviderFactory(factory)
    }

    companion object {
    }
}

/// AndroidAppMain is initial `androidx.appcompat.app.AppCompatActivity`, and must match `activity android:name` in the AndroidMainfest.xml file.
open class MainActivity: AppCompatActivity {
    constructor() {
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        logger.info("starting activity")
        UIApplication.launch(this)
        enableEdgeToEdge()

        setContent {
            val saveableStateHolder = rememberSaveableStateHolder()
            saveableStateHolder.SaveableStateProvider(true) {
                PresentationRootView(ComposeContext())
                SideEffect { saveableStateHolder.removeState(true) }
            }
        }

        AppDelegate.shared.onLaunch()
        handleSharedText(intent)

        // Example of requesting permissions on startup.
        // These must match the permissions in the AndroidManifest.xml file.
        //let permissions = listOf(
        //    Manifest.permission.ACCESS_COARSE_LOCATION,
        //    Manifest.permission.ACCESS_FINE_LOCATION
        //    Manifest.permission.CAMERA,
        //    Manifest.permission.WRITE_EXTERNAL_STORAGE,
        //)
        //let requestTag = 1
        //ActivityCompat.requestPermissions(self, permissions.toTypedArray(), requestTag)
    }

    override fun onStart() {
        logger.info("onStart")
        super.onStart()
    }

    /// The activity is a `singleTask`: a share while it runs arrives here.
    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleSharedText(intent)
    }

    /// A text another app shared with BakePlanner (the browser's page
    /// address) goes to the app; the intent is then marked as taken, so a
    /// recreated activity does not share it a second time.
    private fun handleSharedText(intent: android.content.Intent?) {
        if (intent == null || intent.action != android.content.Intent.ACTION_SEND) {
            return
        }
        if (intent.type?.startsWith("text/") != true) {
            return
        }
        val text = intent.getStringExtra(android.content.Intent.EXTRA_TEXT) ?: return
        intent.action = android.content.Intent.ACTION_MAIN
        intent.removeExtra(android.content.Intent.EXTRA_TEXT)
        AppDelegate.shared.onSharedText(text)
    }

    override fun onResume() {
        super.onResume()
        AppDelegate.shared.onResume()
    }

    override fun onPause() {
        super.onPause()
        AppDelegate.shared.onPause()
    }

    override fun onStop() {
        super.onStop()
        AppDelegate.shared.onStop()
    }

    override fun onDestroy() {
        super.onDestroy()
        AppDelegate.shared.onDestroy()
    }

    override fun onLowMemory() {
        super.onLowMemory()
        AppDelegate.shared.onLowMemory()
    }

    override fun onRestart() {
        logger.info("onRestart")
        super.onRestart()
    }

    override fun onSaveInstanceState(outState: android.os.Bundle): Unit = super.onSaveInstanceState(outState)

    override fun onRestoreInstanceState(bundle: android.os.Bundle) {
        // Usually you restore your state in onCreate(). It is possible to restore it in onRestoreInstanceState() as well, but not very common. (onRestoreInstanceState() is called after onStart(), whereas onCreate() is called before onStart().
        logger.info("onRestoreInstanceState")
        super.onRestoreInstanceState(bundle)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: kotlin.Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        logger.info("onRequestPermissionsResult: ${requestCode}")
    }

    companion object {
    }
}

@Composable
internal fun SyncSystemBarsWithTheme() {
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f

    val transparent = AndroidColor.TRANSPARENT
    val style = if (dark) {
        SystemBarStyle.dark(transparent)
    } else {
        SystemBarStyle.light(transparent, transparent)
    }

    val activity = LocalContext.current as? ComponentActivity
    DisposableEffect(style) {
        activity?.enableEdgeToEdge(
            statusBarStyle = style,
            navigationBarStyle = style
        )
        onDispose { }
    }
}

/// Nunito (res/font, SIL Open Font License) in every weight the app uses,
/// as a Compose font family that resolves weights itself.
@OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
private val nunito = FontFamily(
    Font(R.font.nunito_variable, FontWeight.Normal, variationSettings = FontVariation.Settings(FontVariation.weight(400))),
    Font(R.font.nunito_variable, FontWeight.Medium, variationSettings = FontVariation.Settings(FontVariation.weight(500))),
    Font(R.font.nunito_variable, FontWeight.SemiBold, variationSettings = FontVariation.Settings(FontVariation.weight(600))),
    Font(R.font.nunito_variable, FontWeight.Bold, variationSettings = FontVariation.Settings(FontVariation.weight(700))),
    Font(R.font.nunito_variable, FontWeight.ExtraBold, variationSettings = FontVariation.Settings(FontVariation.weight(800)))
)

/// Material's type scale set in Nunito: the navigation titles, tab labels,
/// buttons and form rows that SkipUI draws from the theme, not from a font
/// the app's Swift names.
private fun nunitoTypography(base: Typography): Typography = Typography(
    displayLarge = base.displayLarge.copy(fontFamily = nunito),
    displayMedium = base.displayMedium.copy(fontFamily = nunito),
    displaySmall = base.displaySmall.copy(fontFamily = nunito),
    headlineLarge = base.headlineLarge.copy(fontFamily = nunito),
    headlineMedium = base.headlineMedium.copy(fontFamily = nunito),
    headlineSmall = base.headlineSmall.copy(fontFamily = nunito),
    titleLarge = base.titleLarge.copy(fontFamily = nunito),
    titleMedium = base.titleMedium.copy(fontFamily = nunito),
    titleSmall = base.titleSmall.copy(fontFamily = nunito),
    bodyLarge = base.bodyLarge.copy(fontFamily = nunito),
    bodyMedium = base.bodyMedium.copy(fontFamily = nunito),
    bodySmall = base.bodySmall.copy(fontFamily = nunito),
    labelLarge = base.labelLarge.copy(fontFamily = nunito),
    labelMedium = base.labelMedium.copy(fontFamily = nunito),
    labelSmall = base.labelSmall.copy(fontFamily = nunito)
)

@Composable
internal fun PresentationRootView(context: ComposeContext) {
    val colorScheme = if (isSystemInDarkTheme()) ColorScheme.dark else ColorScheme.light
    // SkipUI's root keeps the typography of the theme around it, so Nunito
    // set here reaches everything Material draws.
    MaterialTheme(typography = nunitoTypography(MaterialTheme.typography)) {
        PresentationRoot(defaultColorScheme = colorScheme, context = context) { ctx ->
            SyncSystemBarsWithTheme()
            val contentContext = ctx.content()
            Box(modifier = ctx.modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                AppRootView().Compose(context = contentContext)
            }
        }
    }
}
