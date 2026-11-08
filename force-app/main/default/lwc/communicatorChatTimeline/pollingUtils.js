/** Fetches every available poll page and removes items already present in the timeline. */
export async function fetchAllTimelinePages({ fetchPage, cursor, existingMessages = [], pageSize = 50, maxPages = 100 }) {
    const seenIds = new Set(
        (existingMessages || [])
            .map(message => message?.Id || message?.ExternalId__c)
            .filter(Boolean)
    );
    const messages = [];
    let hasMore = true;
    let pageCount = 0;

    while (hasMore && pageCount < maxPages) {
        const previousCursor = cursor;
        // Poll pages are sequential because the next request depends on the prior cursor.
        // eslint-disable-next-line no-await-in-loop
        const page = await fetchPage(cursor, pageSize);
        if (!page) break;
        (page.messages || []).forEach(message => {
            const id = message?.Id || message?.ExternalId__c;
            if (id && !seenIds.has(id)) {
                seenIds.add(id);
                messages.push(message);
            }
        });
        hasMore = page.hasMore === true;
        if (page.nextCursor) cursor = page.nextCursor;
        pageCount++;
        if (hasMore && cursor === previousCursor) break;
    }

    return { messages, cursor, hasMore };
}