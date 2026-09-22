package `in`.nann.slapshot

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.text.BasicText
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.sp

/**
 * The empty shell (spec: platform-delta row "Neither app implements §1–§9 yet"). It launches and
 * shows the title; the scene surface arrives with ADR 0003's spike.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            Column(
                modifier = Modifier.fillMaxSize().background(Color(0xFF1E1B4B)),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                BasicText(stringResource(R.string.app_name), style = TextStyle(color = Color.White, fontSize = 34.sp))
                BasicText(stringResource(R.string.menu_tagline), style = TextStyle(color = Color(0xFFC7D2FE), fontSize = 16.sp))
            }
        }
    }
}
