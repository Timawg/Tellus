package com.pathos.tellus.countries

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.ColorPainter
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.pathos.tellus.R
import com.pathos.tellus.ui.theme.TellusTheme

/**
 * A bar showing the selected country that expands upwards into a searchable
 * list, ported from iOS `ExpandableSelectionButton`.
 */
@Composable
fun CountrySelectionBar(
    countries: List<Country>,
    selected: Country?,
    isExpanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    onSelect: (Country) -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(25.dp)
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(16.dp),
        shape = shape,
        color = MaterialTheme.colorScheme.surfaceContainer.copy(alpha = 0.92f),
        // No shadow: it would show through the translucent background.
        tonalElevation = 3.dp,
    ) {
        Column(Modifier.animateContentSize()) {
            if (isExpanded) {
                // Inside the expanded branch, so each opening starts a fresh search.
                var query by remember { mutableStateOf("") }
                val visible = CountrySearch.filter(countries, query)
                SearchField(
                    query = query,
                    onQueryChange = { query = it },
                    onSubmit = { CountrySearch.submitted(countries, query)?.let(onSelect) },
                )
                CountryList(
                    countries = visible,
                    selected = selected,
                    query = query,
                    onSelect = onSelect,
                )
                HorizontalDivider(Modifier.padding(horizontal = 16.dp))
            }
            SelectedRow(selected = selected, isExpanded = isExpanded, onClick = { onExpandedChange(!isExpanded) })
        }
    }
}

@Composable
private fun SelectedRow(selected: Country?, isExpanded: Boolean, onClick: () -> Unit) {
    val actionLabel = stringResource(if (isExpanded) R.string.close_country_list else R.string.show_country_list)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(role = Role.Button, onClickLabel = actionLabel, onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (selected != null) {
            CountryLabel(selected, Modifier.weight(1f))
        } else {
            Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
            }
        }
        Icon(
            imageVector = if (isExpanded) Icons.Filled.KeyboardArrowDown else Icons.Filled.KeyboardArrowUp,
            contentDescription = null,
        )
    }
}

@Composable
private fun CountryLabel(country: Country, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        FlagImage(country.flagUrl)
        Text(
            text = country.name?.common.orEmpty(),
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 8.dp),
            style = MaterialTheme.typography.bodyLarge,
            textAlign = TextAlign.Center,
        )
        // Balances the flag so the name sits in the middle.
        Spacer(Modifier.width(FlagWidth))
    }
}

@Composable
private fun SearchField(query: String, onQueryChange: (String) -> Unit, onSubmit: () -> Unit) {
    TextField(
        value = query,
        onValueChange = onQueryChange,
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = 12.dp, end = 12.dp, top = 12.dp, bottom = 4.dp),
        placeholder = { Text(stringResource(R.string.search_countries)) },
        leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
        trailingIcon = {
            if (query.isNotEmpty()) {
                IconButton(onClick = { onQueryChange("") }) {
                    Icon(Icons.Filled.Clear, contentDescription = stringResource(R.string.clear_search))
                }
            }
        },
        singleLine = true,
        shape = RoundedCornerShape(14.dp),
        colors = TextFieldDefaults.colors(
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
        ),
        keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.Words,
            autoCorrectEnabled = false,
            imeAction = ImeAction.Search,
        ),
        keyboardActions = KeyboardActions(onSearch = { onSubmit() }),
    )
}

@Composable
private fun CountryList(countries: List<Country>, selected: Country?, query: String, onSelect: (Country) -> Unit) {
    // Open at the current selection rather than the top of the list.
    val listState = rememberLazyListState(
        initialFirstVisibleItemIndex = countries.indexOfFirst { it.cca3 == selected?.cca3 }.coerceAtLeast(0),
    )
    LaunchedEffect(query) {
        if (query.isNotBlank()) listState.scrollToItem(0)
    }
    LazyColumn(
        state = listState,
        modifier = Modifier.heightIn(max = 320.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
        contentPadding = PaddingValues(8.dp),
    ) {
        items(countries, key = { it.cca3 ?: it.hashCode() }) { country ->
            val isSelected = country.cca3 == selected?.cca3
            CountryLabel(
                country = country,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(if (isSelected) MaterialTheme.colorScheme.secondaryContainer else Color.Transparent)
                    .semantics { this.selected = isSelected }
                    .clickable(role = Role.Button) { onSelect(country) }
                    .padding(horizontal = 16.dp, vertical = 10.dp),
            )
        }
        if (countries.isEmpty()) {
            item {
                Text(
                    text = stringResource(R.string.no_matches),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 24.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

private val FlagWidth = 40.dp

/** A country's flag. It always takes its full size, so the layout doesn't jump when the image arrives. */
@Composable
fun FlagImage(url: String?, modifier: Modifier = Modifier) {
    AsyncImage(
        model = url,
        contentDescription = null,
        modifier = modifier
            .size(width = FlagWidth, height = 25.dp)
            .clip(RoundedCornerShape(3.dp)),
        placeholder = ColorPainter(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f)),
        error = ColorPainter(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f)),
    )
}

private val previewCountries = listOf("Sweden" to "SWE", "Norway" to "NOR", "Finland" to "FIN").map { (name, code) ->
    Country(name = Country.Name(common = name), cca3 = code, translations = emptyMap(), latlng = emptyList())
}

@Preview
@Composable
private fun CollapsedPreview() {
    TellusTheme {
        CountrySelectionBar(previewCountries, previewCountries[0], isExpanded = false, onExpandedChange = {}, onSelect = {})
    }
}

@Preview
@Composable
private fun LoadingPreview() {
    TellusTheme {
        CountrySelectionBar(emptyList(), selected = null, isExpanded = false, onExpandedChange = {}, onSelect = {})
    }
}

@Preview
@Composable
private fun ExpandedPreview() {
    TellusTheme {
        CountrySelectionBar(previewCountries, previewCountries[1], isExpanded = true, onExpandedChange = {}, onSelect = {})
    }
}
