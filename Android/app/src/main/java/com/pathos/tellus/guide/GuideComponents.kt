package com.pathos.tellus.guide

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException

/** A grouped list section, like a SwiftUI `Section` in an inset list. */
@Composable
fun GuideSection(
    header: String?,
    modifier: Modifier = Modifier,
    footer: (@Composable ColumnScope.() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        if (header != null) {
            Text(
                text = header,
                modifier = Modifier
                    .padding(start = 16.dp, bottom = 6.dp)
                    .semantics { heading() },
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Surface(
            shape = RoundedCornerShape(16.dp),
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
                content = content,
            )
        }
        if (footer != null) {
            Column(
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                CompositionLocalProvider(
                    LocalTextStyle provides MaterialTheme.typography.bodySmall,
                    LocalContentColor provides MaterialTheme.colorScheme.onSurfaceVariant,
                ) { footer() }
            }
        }
    }
}

/** A label on the left and its value on the right, like `LabeledContent`. */
@Composable
fun LabeledRow(label: String, value: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(label, modifier = Modifier.weight(1f))
        Text(
            text = value,
            modifier = Modifier.weight(1f),
            textAlign = TextAlign.End,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** Secondary text explaining an empty or failed state. */
@Composable
fun SecondaryText(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

/** A row with a spinner and what's loading. */
@Composable
fun LoadingRow(text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
        SecondaryText(text)
    }
}

@Composable
fun RetryButton(onRetry: () -> Unit) {
    TextButton(onClick = onRetry) { Text("Retry") }
}

/** An underlined link to a data source, opened in the browser. */
@Composable
fun SourceLink(title: String, url: String, modifier: Modifier = Modifier) {
    val text = buildAnnotatedString {
        withLink(
            LinkAnnotation.Url(
                url,
                TextLinkStyles(
                    SpanStyle(color = MaterialTheme.colorScheme.primary, textDecoration = TextDecoration.Underline),
                ),
            ),
        ) { append(title) }
    }
    Text(text, modifier, style = MaterialTheme.typography.bodySmall)
}

/** What an on-demand load in a section has produced so far. */
sealed interface LoadState<out T> {
    data object Loading : LoadState<Nothing>
    data class Loaded<T>(val value: T) : LoadState<T>
    data object Failed : LoadState<Nothing>
}

/**
 * Runs [load] while the caller is on screen, like the iOS sections'
 * `.task`, and restarts it when [key] changes or retry is called.
 * Cancellation is routine cleanup, not a failure.
 */
@Composable
fun <T> rememberLoad(key: Any?, load: suspend () -> T): Pair<LoadState<T>, () -> Unit> {
    var attempt by remember(key) { mutableIntStateOf(0) }
    var state by remember(key) { mutableStateOf<LoadState<T>>(LoadState.Loading) }
    LaunchedEffect(key, attempt) {
        state = LoadState.Loading
        state = try {
            LoadState.Loaded(load())
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            LoadState.Failed
        }
    }
    return state to { attempt++ }
}
