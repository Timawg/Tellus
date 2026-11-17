package com.pathos.tellus.guide.advisories

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.pathos.tellus.guide.GuideSection
import com.pathos.tellus.guide.GuideTopic
import com.pathos.tellus.guide.LoadingRow
import com.pathos.tellus.guide.SecondaryText
import com.pathos.tellus.guide.SourceLink
import com.pathos.tellus.guide.StatusDot
import com.pathos.tellus.guide.colors

/**
 * The travel advice for a tab, ported from iOS `TravelAdviceSection`. Entry
 * also leads with the advisory itself.
 */
@Composable
fun TravelAdviceContent(
    topic: GuideTopic,
    guide: DestinationGuide?,
    advisoryStatus: AdvisoryStatus?,
    isLoading: Boolean,
    loadFailed: Boolean,
) {
    when {
        guide != null -> {
            if (topic == GuideTopic.ENTRY) {
                val heading: @Composable () -> Unit = { AdvisoryHeading(advisoryStatus) }
                if (guide.advisories.isNotEmpty()) {
                    AdviceTopics(guide.advisories, heading)
                } else {
                    advisoryStatus?.data?.eng?.advisoryText?.takeIf { it.isNotEmpty() }?.let { summary ->
                        GuideSection(header = null) {
                            heading()
                            Text(summary)
                        }
                    }
                }
            }
            val sections = guide.sections(topic)
            if (sections.isEmpty()) {
                GuideSection(header = null) { SecondaryText("No ${topicHeading(topic).lowercase()} advice") }
            } else {
                AdviceTopics(sections) { Text(topicHeading(topic), style = MaterialTheme.typography.titleSmall) }
            }
        }
        isLoading -> GuideSection(header = null) { LoadingRow("Loading advice…") }
        else -> GuideSection(header = null) {
            SecondaryText(if (loadFailed) "Couldn’t load travel advice" else "No travel advice")
            if (topic == GuideTopic.ENTRY) {
                SourceLink("Browse Canadian travel advisories", "https://travel.gc.ca/travelling/advisories")
            }
        }
    }
}

/** Heading for a topic's advice list. */
private fun topicHeading(topic: GuideTopic) = when (topic) {
    GuideTopic.OVERVIEW -> "Overview"
    GuideTopic.ENTRY -> "Entry requirements"
    GuideTopic.HEALTH -> "Health"
    GuideTopic.LAWS -> "Laws & culture"
    GuideTopic.CLIMATE -> "Natural disasters & climate"
}

@Composable
private fun AdvisoryHeading(status: AdvisoryStatus?) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        status?.colors?.let { StatusDot(it, 16.dp, Modifier.clearAndSetSemantics { }) }
        Text("Travel advisory", style = MaterialTheme.typography.titleSmall)
    }
}

/** The introduction, then each titled topic as an expandable row. */
@Composable
private fun AdviceTopics(sections: List<AdviceSection>, heading: @Composable () -> Unit) {
    val introduction = sections.firstOrNull { it.title == null }
    val topics = sections.filter { it.title != null }
    if (introduction != null) {
        GuideSection(header = null) {
            heading()
            AdviceBlocks(introduction.blocks)
        }
    }
    if (topics.isNotEmpty()) {
        GuideSection(header = if (introduction == null) null else "Topics") {
            if (introduction == null) heading()
            topics.forEach { TopicRow(it) }
        }
    }
}

@Composable
private fun TopicRow(section: AdviceSection) {
    var expanded by rememberSaveable(section.id, section.title) { mutableStateOf(false) }
    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(role = Role.Button) { expanded = !expanded }
                .semantics { stateDescription = if (expanded) "Expanded" else "Collapsed" }
                .padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(section.title.orEmpty(), Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
            Icon(if (expanded) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown, contentDescription = null)
        }
        if (expanded) AdviceBlocks(section.blocks, Modifier.padding(vertical = 4.dp))
    }
}

/** Paragraphs, bullets and subheadings, with links (including `tel:` numbers) tappable. */
@Composable
fun AdviceBlocks(blocks: List<AdviceSection.Block>, modifier: Modifier = Modifier) {
    val linkStyles = TextLinkStyles(SpanStyle(color = MaterialTheme.colorScheme.primary, textDecoration = TextDecoration.Underline))
    val style = MaterialTheme.typography.bodyMedium
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        blocks.forEach { block ->
            when (block) {
                is AdviceSection.Block.Paragraph -> Text(block.text.annotated(linkStyles), style = style)
                is AdviceSection.Block.Bullet -> Row(
                    modifier = Modifier.padding(start = (4 + 12 * block.depth).dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(if (block.depth % 2 == 0) "•" else "◦", style = style, modifier = Modifier.clearAndSetSemantics { })
                    Text(block.text.annotated(linkStyles), style = style)
                }
                is AdviceSection.Block.Subheading -> Text(
                    block.text,
                    modifier = Modifier.padding(top = 4.dp),
                    style = style,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

private fun AdviceText.annotated(styles: TextLinkStyles): AnnotatedString =
    AnnotatedString.Builder(text).apply {
        links.forEach { addLink(LinkAnnotation.Url(it.url, styles), it.start, it.end) }
    }.toAnnotatedString()

/** Where the advice comes from and its licence, as in iOS `GuideAdviceSource`. */
@Composable
fun GuideAdviceSource(guide: DestinationGuide) {
    GuideSection(header = null) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            val small = MaterialTheme.typography.bodySmall
            val color = MaterialTheme.colorScheme.onSurfaceVariant
            Text("Government of Canada advice, adapted for travellers.", style = small, color = color)
            if (guide.updated.isNotEmpty()) Text("Updated ${guide.updated}", style = small, color = color)
            SourceLink("Full advisory on travel.gc.ca", guide.adviceUrl)
            SourceLink("Open Government Licence – Canada", "https://open.canada.ca/en/open-government-licence-canada")
        }
    }
}
