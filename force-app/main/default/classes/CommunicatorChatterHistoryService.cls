public without sharing class CommunicatorChatterHistoryService {
    private static final Integer MIN_PAGE_SIZE = 5;
    private static final Integer DEFAULT_PAGE_SIZE = 20;
    private static final Integer MAX_PAGE_SIZE = 50;
    private static final Integer MAX_SEARCH_RESULTS = 50;
    private static final Integer POST_BODY_SEARCH_BATCH_SIZE = 1000;
    private static final Integer MAX_POST_BODY_SEARCH_ROWS = 45000;
    private static final Integer MAX_ATTACHMENT_SEARCH_FEED_ITEMS = 1000;
    private static final Integer MAX_ATTACHMENT_SEARCH_COMMENTS = 500;
    private static final Integer MIN_SEARCH_TERM_LENGTH = 2;
    private static final Integer MAX_COMMENTS_PER_PAGE = 500;
    private static final String CURSOR_DIRECTION_OLDER = 'older';
    private static final String CURSOR_DIRECTION_NEWER = 'newer';
    private static final String PAGING_DIRECTION_OLDER = 'older';
    private static final String PAGING_DIRECTION_NEWER = 'newer';
    private static final String FEED_TYPE_CONTENT_POST = 'ContentPost';
    private static final String FEED_TYPE_LINK_POST = 'LinkPost';
    private static final String COMMENT_TYPE_CONTENT_COMMENT = 'ContentComment';
    private static final String INLINE_IMAGE_SRC_PREFIX = 'sfdc://';
    private static final String SALESFORCE_ID_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    @TestVisible
    private static Integer postBodySearchBatchSizeOverrideForTest;
    private static final String ERROR_INACCESSIBLE_ATTACHMENT = 'Arquivo do Historico Chatter nao encontrado ou inacessivel.';

    private static final String ERROR_INVALID_OPPORTUNITY = 'Oportunidade inválida.';
    private static final String ERROR_INACCESSIBLE_OPPORTUNITY = 'Oportunidade não encontrada ou inacessível.';
    private static final String ERROR_INVALID_CURSOR = 'Cursor inválido.';
    private static final String ERROR_UNEXPECTED = 'Não foi possível carregar o Histórico Chatter.';

    private static final Set<String> ALLOWED_PARENT_OBJECT_API_NAMES = new Set<String>{
        'Opportunity',
        'Quote',
        'AnaliseFinanceira__c',
        'AprovacaoBancaria__c',
        'Repasse__c'
    };
    private static final Set<String> ALLOWED_FEED_TYPES = new Set<String>{ 'TextPost', FEED_TYPE_LINK_POST, FEED_TYPE_CONTENT_POST };
    private static final Set<String> IMAGE_FILE_TYPES = new Set<String>{
        'BMP',
        'GIF',
        'HEIC',
        'JPG',
        'JPEG',
        'PNG',
        'TIF',
        'TIFF',
        'WEBP'
    };
    private static final Set<String> IMAGE_EXTENSIONS = new Set<String>{
        'bmp',
        'gif',
        'heic',
        'jpg',
        'jpeg',
        'png',
        'tif',
        'tiff',
        'webp'
    };
    private static final String ANALISE_FINANCEIRA_RECORD_TYPE_ANALISE_CREDITO = 'AnaliseCredito';
    private static final Set<String> ANALISE_FINANCEIRA_RECORD_TYPES_APURACAO_RENDA = new Set<String>{
        'ApuracaoRendaOportunidade',
        'ApuracaoRendaConta'
    };
    private static final Map<String, String> ORIGIN_LABEL_BY_OBJECT_API_NAME = new Map<String, String>{
        'Opportunity' => 'Oportunidade',
        'Quote' => 'Cotação',
        'AnaliseFinanceira__c' => 'Análise Financeira',
        'AprovacaoBancaria__c' => 'Aprovação Bancária',
        'Repasse__c' => 'Repasse'
    };

    @AuraEnabled(cacheable=false)
    public static ChatterHistoryPageDTO getChatterHistoryPage(
        Id threadId,
        Id opportunityId,
        String cursor,
        Integer pageSize,
        String pagingDirection
    ) {
        try {
            Opportunity rootOpportunity = getAuthorizedOpportunity(threadId, opportunityId);
            Integer normalizedPageSize = normalizePageSize(pageSize);
            String normalizedPagingDirection = normalizePagingDirection(pagingDirection);
            CursorState cursorState = parseCursor(cursor, rootOpportunity.Id, normalizedPagingDirection);
            Map<Id, ParentRef> parentRefsById = resolveChatterParentRefs(rootOpportunity);

            return queryFeedItems(rootOpportunity.Id, parentRefsById, cursorState, normalizedPageSize, normalizedPagingDirection);
        } catch (ChatterHistoryException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            if (Test.isRunningTest()) {
                throw ex;
            }
            throw new AuraHandledException(ERROR_UNEXPECTED);
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<ChatterSearchResultDTO> searchChatterHistory(Id threadId, Id opportunityId, String keyword) {
        try {
            Opportunity rootOpportunity = getAuthorizedOpportunity(threadId, opportunityId);
            Map<Id, ParentRef> parentRefsById = resolveChatterParentRefs(rootOpportunity);
            return searchFeedItems(parentRefsById, keyword);
        } catch (ChatterHistoryException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            if (Test.isRunningTest()) {
                throw ex;
            }
            throw new AuraHandledException(ERROR_UNEXPECTED);
        }
    }

    @AuraEnabled(cacheable=false)
    public static ChatterHistoryPageDTO getChatterHistoryPageForFeedItem(
        Id threadId,
        Id opportunityId,
        Id feedItemId,
        Integer pageSize
    ) {
        try {
            Opportunity rootOpportunity = getAuthorizedOpportunity(threadId, opportunityId);
            Integer normalizedPageSize = normalizePageSize(pageSize);
            Map<Id, ParentRef> parentRefsById = resolveChatterParentRefs(rootOpportunity);

            return queryFeedItemsFromTarget(rootOpportunity.Id, parentRefsById, feedItemId, normalizedPageSize);
        } catch (ChatterHistoryException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            if (Test.isRunningTest()) {
                throw ex;
            }
            throw new AuraHandledException(ERROR_UNEXPECTED);
        }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorDTOs.AttachmentFileDTO getAttachmentFile(
        Id threadId,
        Id opportunityId,
        String contentDocumentId,
        String contentVersionId,
        Id feedItemId,
        Id feedCommentId
    ) {
        try {
            Opportunity rootOpportunity = getAuthorizedOpportunity(threadId, opportunityId);
            Map<Id, ParentRef> parentRefsById = resolveChatterParentRefs(rootOpportunity);
            Id resolvedContentDocumentId = resolveAttachmentContentDocumentId(contentDocumentId, contentVersionId);

            if (!isAuthorizedAttachmentForExpandedHistory(
                resolvedContentDocumentId,
                parentRefsById.keySet(),
                feedItemId,
                feedCommentId
            )) {
                throw new ChatterHistoryException(ERROR_INACCESSIBLE_ATTACHMENT);
            }

            return buildAttachmentFileDto(queryAttachmentBinaryVersion(resolvedContentDocumentId));
        } catch (ChatterHistoryException ex) {
            throw new AuraHandledException(ex.getMessage());
        } catch (Exception ex) {
            if (Test.isRunningTest()) {
                throw ex;
            }
            throw new AuraHandledException(ERROR_UNEXPECTED);
        }
    }

    private static Opportunity getAuthorizedOpportunity(Id threadId, Id expectedOpportunityId) {
        if (expectedOpportunityId == null || expectedOpportunityId.getSObjectType() != Opportunity.SObjectType) {
            throw new ChatterHistoryException(ERROR_INVALID_OPPORTUNITY);
        }

        Opportunity authorizedOpportunity;
        try {
            authorizedOpportunity = CommunicatorThreadService.resolveAuthorizedOpportunityForChatterHistory(
                threadId,
                expectedOpportunityId
            );
        } catch (CommunicatorException ex) {
            throw new ChatterHistoryException(ERROR_INACCESSIBLE_OPPORTUNITY);
        }

        List<String> selectedFields = new List<String>{
            'Id',
            'ApuracaoRenda__c',
            'AnaliseCredito__c',
            'AprovacaoBancaria__c'
        };

        Opportunity opportunity = queryAuthorizedOpportunityRecord(authorizedOpportunity.Id, selectedFields);
        if (opportunity == null) {
            throw new ChatterHistoryException(ERROR_INACCESSIBLE_OPPORTUNITY);
        }
        return opportunity;
    }

    private static Boolean isReadableField(Map<String, Schema.SObjectField> fieldMap, String fieldApiName) {
        return fieldMap != null
            && fieldMap.containsKey(fieldApiName)
            && fieldMap.get(fieldApiName).getDescribe().isAccessible();
    }

    private static Integer normalizePageSize(Integer pageSize) {
        // Page size is normalized to keep the client contract stable and bounded.
        if (pageSize == null) return DEFAULT_PAGE_SIZE;
        if (pageSize < MIN_PAGE_SIZE) return MIN_PAGE_SIZE;
        if (pageSize > MAX_PAGE_SIZE) return MAX_PAGE_SIZE;
        return pageSize;
    }

    private static String normalizePagingDirection(String pagingDirection) {
        String normalizedDirection = String.isBlank(pagingDirection)
            ? PAGING_DIRECTION_OLDER
            : pagingDirection.trim().toLowerCase();
        if (normalizedDirection != PAGING_DIRECTION_OLDER && normalizedDirection != PAGING_DIRECTION_NEWER) {
            throw new ChatterHistoryException(ERROR_INVALID_CURSOR);
        }
        return normalizedDirection;
    }

    private static CursorState parseCursor(String cursor, Id opportunityId, String pagingDirection) {
        if (String.isBlank(cursor)) return null;

        try {
            String serializedCursor = EncodingUtil.convertFromHex(cursor).toString();
            CursorState cursorState = (CursorState) JSON.deserialize(serializedCursor, CursorState.class);
            if (cursorState == null
                || cursorState.opportunityId != String.valueOf(opportunityId)
                || cursorState.createdDate == null
                || cursorState.feedItemId == null
                || cursorState.direction != pagingDirection) {
                throw new ChatterHistoryException(ERROR_INVALID_CURSOR);
            }
            return cursorState;
        } catch (ChatterHistoryException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new ChatterHistoryException(ERROR_INVALID_CURSOR);
        }
    }

    private static String buildCursor(Id opportunityId, DateTime createdDate, Id feedItemId, String direction) {
        CursorState cursorState = new CursorState();
        cursorState.opportunityId = String.valueOf(opportunityId);
        cursorState.createdDate = createdDate;
        cursorState.feedItemId = feedItemId;
        cursorState.direction = direction;

        return EncodingUtil.convertToHex(Blob.valueOf(JSON.serialize(cursorState)));
    }

    private static Map<Id, ParentRef> resolveChatterParentRefs(Opportunity rootOpportunity) {
        Map<Id, ParentRef> parentRefsById = new Map<Id, ParentRef>();
        addParentRef(parentRefsById, rootOpportunity.Id, 'Opportunity');
        addQuoteRefs(parentRefsById, rootOpportunity.Id);
        addRepasseRefs(parentRefsById, rootOpportunity.Id);
        Set<Id> analiseIds = addAnaliseFinanceiraRefs(parentRefsById, rootOpportunity);
        addAprovacaoBancariaRefs(parentRefsById, rootOpportunity, analiseIds);
        return parentRefsById;
    }

    private static void addQuoteRefs(Map<Id, ParentRef> parentRefsById, Id opportunityId) {
        for (Quote quoteRecord : [
            SELECT Id
            FROM Quote
            WHERE OpportunityId = :opportunityId
        ]) {
            addParentRef(parentRefsById, quoteRecord.Id, 'Quote');
        }
    }

    private static void addRepasseRefs(Map<Id, ParentRef> parentRefsById, Id opportunityId) {
        for (Repasse__c repasse : [
            SELECT Id
            FROM Repasse__c
            WHERE Oportunidade__c = :opportunityId
        ]) {
            addParentRef(parentRefsById, repasse.Id, 'Repasse__c');
        }
    }

    private static Set<Id> addAnaliseFinanceiraRefs(Map<Id, ParentRef> parentRefsById, Opportunity rootOpportunity) {
        Set<Id> directAnaliseIds = getOpportunityLookupIds(
            rootOpportunity,
            new List<String>{ 'ApuracaoRenda__c', 'AnaliseCredito__c' }
        );
        Set<Id> analiseIds = new Set<Id>();
        Id opportunityId = rootOpportunity.Id;

        List<String> clauses = new List<String>();
        clauses.add('Oportunidade__c = :opportunityId');
        if (!directAnaliseIds.isEmpty()) {
            clauses.add('Id IN :directAnaliseIds');
        }

        String soql =
            'SELECT Id, RecordTypeId' +
            ' FROM AnaliseFinanceira__c WHERE ' + String.join(clauses, ' OR ');
        for (AnaliseFinanceira__c analise : Database.query(soql)) {
            analiseIds.add(analise.Id);
            addParentRef(
                parentRefsById,
                analise.Id,
                'AnaliseFinanceira__c',
                resolveAnaliseFinanceiraOriginLabelByRecordTypeId(analise.RecordTypeId)
            );
        }
        return analiseIds;
    }

    private static void addAprovacaoBancariaRefs(
        Map<Id, ParentRef> parentRefsById,
        Opportunity rootOpportunity,
        Set<Id> analiseIds
    ) {
        Set<Id> directAprovacaoIds = getOpportunityLookupIds(rootOpportunity, new List<String>{ 'AprovacaoBancaria__c' });

        List<String> clauses = new List<String>();
        if (!analiseIds.isEmpty()) {
            clauses.add('AnaliseCredito__c IN :analiseIds');
        }
        if (!directAprovacaoIds.isEmpty()) {
            clauses.add('Id IN :directAprovacaoIds');
        }
        if (clauses.isEmpty()) {
            return;
        }

        String soql = 'SELECT Id FROM AprovacaoBancaria__c WHERE ' + String.join(clauses, ' OR ');
        for (AprovacaoBancaria__c aprovacao : Database.query(soql)) {
            addParentRef(parentRefsById, aprovacao.Id, 'AprovacaoBancaria__c');
        }
    }

    private static Set<Id> getOpportunityLookupIds(Opportunity rootOpportunity, List<String> fieldApiNames) {
        Set<Id> lookupIds = new Set<Id>();
        Map<String, Object> populatedFields = rootOpportunity.getPopulatedFieldsAsMap();
        for (String fieldApiName : fieldApiNames) {
            Object rawValue = populatedFields.containsKey(fieldApiName) ? populatedFields.get(fieldApiName) : null;
            if (rawValue != null) {
                lookupIds.add((Id) rawValue);
            }
        }
        return lookupIds;
    }

    private static Opportunity queryAuthorizedOpportunityRecord(Id opportunityId, List<String> selectedFields) {
        if (opportunityId == null || selectedFields == null || selectedFields.isEmpty()) {
            return null;
        }

        String soql =
            'SELECT ' + String.join(selectedFields, ', ') +
            ' FROM Opportunity WHERE Id = :opportunityId LIMIT 1';
        List<Opportunity> opportunities = Database.query(soql);
        return opportunities.isEmpty() ? null : opportunities[0];
    }

    private static Boolean isObjectReadable(Schema.SObjectType objectType) {
        return objectType != null && objectType.getDescribe().isAccessible();
    }

    private static Boolean isFieldReadable(Schema.SObjectType objectType, String fieldApiName) {
        if (objectType == null || String.isBlank(fieldApiName)) return false;

        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
        return isReadableField(fieldMap, fieldApiName);
    }

    private static void addParentRef(Map<Id, ParentRef> parentRefsById, Id recordId, String objectApiName) {
        addParentRef(parentRefsById, recordId, objectApiName, null);
    }

    private static void addParentRef(
        Map<Id, ParentRef> parentRefsById,
        Id recordId,
        String objectApiName,
        String originLabel
    ) {
        if (recordId == null || !ALLOWED_PARENT_OBJECT_API_NAMES.contains(objectApiName)) {
            return;
        }

        ParentRef parentRef = new ParentRef();
        parentRef.recordId = recordId;
        parentRef.objectApiName = objectApiName;
        parentRef.originLabel = String.isBlank(originLabel)
            ? getDefaultOriginLabel(objectApiName)
            : originLabel;
        parentRefsById.put(recordId, parentRef);
    }

    private static String getDefaultOriginLabel(String objectApiName) {
        return ORIGIN_LABEL_BY_OBJECT_API_NAME.containsKey(objectApiName)
            ? ORIGIN_LABEL_BY_OBJECT_API_NAME.get(objectApiName)
            : 'Registro relacionado';
    }

    private static List<String> buildFeedItemSelectedFields(Boolean includeLinkFields) {
        List<String> selectedFields = new List<String>{
            'Id',
            'ParentId',
            'CreatedById',
            'CreatedDate',
            'Body',
            'Type'
        };
        if (includeLinkFields == true && isFieldReadable(FeedItem.SObjectType, 'LinkUrl')) {
            selectedFields.add('LinkUrl');
        }
        if (includeLinkFields == true && isFieldReadable(FeedItem.SObjectType, 'Title')) {
            selectedFields.add('Title');
        }
        if (canReadUserName()) {
            selectedFields.add('CreatedBy.Name');
        }
        return selectedFields;
    }

    @TestVisible
    private static String resolveAnaliseFinanceiraOriginLabel(String recordTypeDeveloperName) {
        if (recordTypeDeveloperName == ANALISE_FINANCEIRA_RECORD_TYPE_ANALISE_CREDITO) {
            return 'Análise de Crédito';
        }
        if (ANALISE_FINANCEIRA_RECORD_TYPES_APURACAO_RENDA.contains(recordTypeDeveloperName)) {
            return 'Apuração de Renda';
        }
        return getDefaultOriginLabel('AnaliseFinanceira__c');
    }

    @TestVisible
    private static String resolveAnaliseFinanceiraOriginLabelByRecordTypeId(Id recordTypeId) {
        if (recordTypeId == null) {
            return getDefaultOriginLabel('AnaliseFinanceira__c');
        }

        Map<Id, Schema.RecordTypeInfo> recordTypeInfosById =
            Schema.SObjectType.AnaliseFinanceira__c.getRecordTypeInfosById();
        Schema.RecordTypeInfo recordTypeInfo = recordTypeInfosById.get(recordTypeId);
        return recordTypeInfo == null
            ? getDefaultOriginLabel('AnaliseFinanceira__c')
            : resolveAnaliseFinanceiraOriginLabel(recordTypeInfo.getDeveloperName());
    }

    private static ChatterHistoryPageDTO queryFeedItems(
        Id opportunityId,
        Map<Id, ParentRef> parentRefsById,
        CursorState cursorState,
        Integer pageSize,
        String pagingDirection
    ) {
        ChatterHistoryPageDTO page = new ChatterHistoryPageDTO();
        if (parentRefsById == null || parentRefsById.isEmpty()) {
            return page;
        }

        Set<Id> parentIds = parentRefsById.keySet();
        Set<String> allowedFeedTypes = ALLOWED_FEED_TYPES;
        Integer queryLimit = pageSize + 1;
        DateTime cursorDate = cursorState == null ? null : cursorState.createdDate;
        Id cursorFeedItemId = cursorState == null ? null : cursorState.feedItemId;

        List<String> selectedFields = buildFeedItemSelectedFields(true);
        String soql =
            'SELECT ' + String.join(selectedFields, ', ');
        soql +=
            ' FROM FeedItem' +
            ' WHERE ParentId IN :parentIds' +
            ' AND Type IN :allowedFeedTypes';
        if (cursorState != null) {
            if (pagingDirection == PAGING_DIRECTION_NEWER) {
                soql += ' AND (CreatedDate > :cursorDate OR (CreatedDate = :cursorDate AND Id > :cursorFeedItemId))';
            } else {
                soql += ' AND (CreatedDate < :cursorDate OR (CreatedDate = :cursorDate AND Id < :cursorFeedItemId))';
            }
        }
        soql += pagingDirection == PAGING_DIRECTION_NEWER
            ? ' ORDER BY CreatedDate ASC, Id ASC LIMIT :queryLimit'
            : ' ORDER BY CreatedDate DESC, Id DESC LIMIT :queryLimit';

        List<FeedItem> feedItems = Database.query(soql);
        Boolean hasMore = feedItems.size() > pageSize;
        if (hasMore) {
            feedItems.remove(feedItems.size() - 1);
        }

        return buildChatterHistoryPage(opportunityId, parentRefsById, feedItems, hasMore, pagingDirection);
    }

    private static ChatterHistoryPageDTO queryFeedItemsFromTarget(
        Id opportunityId,
        Map<Id, ParentRef> parentRefsById,
        Id feedItemId,
        Integer pageSize
    ) {
        ChatterHistoryPageDTO page = new ChatterHistoryPageDTO();
        if (parentRefsById == null
            || parentRefsById.isEmpty()
            || feedItemId == null
            || feedItemId.getSObjectType() != FeedItem.SObjectType) {
            return page;
        }

        Set<Id> parentIds = parentRefsById.keySet();
        Set<String> allowedFeedTypes = ALLOWED_FEED_TYPES;
        List<FeedItem> targets = [
            SELECT Id, ParentId, CreatedDate, Type
            FROM FeedItem
            WHERE Id = :feedItemId
            AND ParentId IN :parentIds
            AND Type IN :allowedFeedTypes
            LIMIT 1
        ];
        if (targets.isEmpty()) {
            return page;
        }

        FeedItem targetFeedItem = targets[0];
        DateTime targetCreatedDate = targetFeedItem.CreatedDate;
        Id targetFeedItemId = targetFeedItem.Id;
        Integer recordsThroughTarget = [
            SELECT COUNT()
            FROM FeedItem
            WHERE ParentId IN :parentIds
            AND Type IN :allowedFeedTypes
            AND (
                CreatedDate < :targetCreatedDate
                OR (CreatedDate = :targetCreatedDate AND (Id = :targetFeedItemId OR Id < :targetFeedItemId))
            )
        ];
        Integer queryLimit = calculateTargetNavigationQueryLimit(recordsThroughTarget, pageSize);
        List<String> selectedFields = buildFeedItemSelectedFields(true);
        String soql =
            'SELECT ' + String.join(selectedFields, ', ') +
            ' FROM FeedItem' +
            ' WHERE ParentId IN :parentIds' +
            ' AND Type IN :allowedFeedTypes' +
            ' ORDER BY CreatedDate ASC, Id ASC' +
            ' LIMIT :queryLimit';

        List<FeedItem> feedItems = Database.query(soql);
        Boolean hasMore = feedItems.size() == queryLimit;
        if (hasMore) {
            feedItems.remove(feedItems.size() - 1);
        }

        return buildChatterHistoryPage(opportunityId, parentRefsById, feedItems, hasMore, PAGING_DIRECTION_NEWER);
    }

    private static Integer calculateTargetNavigationQueryLimit(Integer recordsThroughTarget, Integer pageSize) {
        Integer normalizedPageSize = normalizePageSize(pageSize);
        Integer targetPageEnd = normalizedPageSize;
        while (targetPageEnd < recordsThroughTarget) {
            targetPageEnd += normalizedPageSize;
        }
        return targetPageEnd + 1;
    }

    private static ChatterHistoryPageDTO buildChatterHistoryPage(
        Id opportunityId,
        Map<Id, ParentRef> parentRefsById,
        List<FeedItem> feedItems,
        Boolean hasMore,
        String pagingDirection
    ) {
        ChatterHistoryPageDTO page = new ChatterHistoryPageDTO();
        if (feedItems == null) {
            feedItems = new List<FeedItem>();
        }

        page.hasMore = hasMore == true;
        page.returnedCount = feedItems.size();
        if (hasMore && !feedItems.isEmpty()) {
            FeedItem boundaryFeedItem = feedItems[feedItems.size() - 1];
            page.previousPageCursor = buildCursor(
                opportunityId,
                boundaryFeedItem.CreatedDate,
                boundaryFeedItem.Id,
                pagingDirection
            );
        }

        CommentQueryResult commentQueryResult = queryCommentsForPage(feedItems);
        AttachmentQueryResult attachmentQueryResult = queryAttachmentsForPage(feedItems, commentQueryResult);
        Map<Id, String> authorPhotoUrlByUserId = resolveAuthorPhotoUrls(feedItems, commentQueryResult);
        page.commentsTruncated = commentQueryResult.commentsTruncated;

        List<FeedItem> orderedFeedItems = pagingDirection == PAGING_DIRECTION_NEWER
            ? feedItems
            : reverseFeedItems(feedItems);

        for (FeedItem orderedFeedItem : orderedFeedItems) {
            PostDTO post = toPostDTO(orderedFeedItem, parentRefsById.get(orderedFeedItem.ParentId));
            post.authorPhotoUrl = authorPhotoUrlByUserId.get(post.authorId);
            if (attachmentQueryResult.inlineImagesByPostId.containsKey(post.feedItemId)) {
                post.inlineImages.addAll(attachmentQueryResult.inlineImagesByPostId.get(post.feedItemId));
            }
            if (attachmentQueryResult.attachmentsByPostId.containsKey(post.feedItemId)) {
                post.attachments.addAll(attachmentQueryResult.attachmentsByPostId.get(post.feedItemId));
                post.attachments.sort();
            }
            if (commentQueryResult.commentsByFeedItemId.containsKey(post.feedItemId)) {
                for (CommentDTO comment : commentQueryResult.commentsByFeedItemId.get(post.feedItemId)) {
                    comment.authorPhotoUrl = authorPhotoUrlByUserId.get(comment.authorId);
                    if (attachmentQueryResult.inlineImagesByCommentId.containsKey(comment.feedCommentId)) {
                        comment.inlineImages.addAll(attachmentQueryResult.inlineImagesByCommentId.get(comment.feedCommentId));
                    }
                    if (attachmentQueryResult.attachmentsByCommentId.containsKey(comment.feedCommentId)) {
                        comment.attachments.addAll(attachmentQueryResult.attachmentsByCommentId.get(comment.feedCommentId));
                        comment.attachments.sort();
                    }
                    if (shouldReturnComment(comment)) {
                        post.comments.add(comment);
                    }
                }
            }
            if (shouldReturnPost(post)) {
                page.posts.add(post);
            }
        }
        page.returnedCount = page.posts.size();
        return page;
    }

    private static List<FeedItem> reverseFeedItems(List<FeedItem> feedItems) {
        List<FeedItem> orderedFeedItems = new List<FeedItem>();
        if (feedItems == null) {
            return orderedFeedItems;
        }

        for (Integer index = feedItems.size() - 1; index >= 0; index--) {
            orderedFeedItems.add(feedItems[index]);
        }
        return orderedFeedItems;
    }

    private static List<ChatterSearchResultDTO> searchFeedItems(
        Map<Id, ParentRef> parentRefsById,
        String keyword
    ) {
        if (parentRefsById == null || parentRefsById.isEmpty()) {
            return new List<ChatterSearchResultDTO>();
        }
        if (String.isBlank(keyword)) {
            throw new ChatterHistoryException('Termo de busca invalido.');
        }

        String trimmedKeyword = keyword.trim();
        if (trimmedKeyword.length() < MIN_SEARCH_TERM_LENGTH) {
            return new List<ChatterSearchResultDTO>();
        }

        Set<Id> parentIds = parentRefsById.keySet();
        String likePattern = '%' + escapeLikeKeyword(trimmedKeyword) + '%';

        List<FeedItem> matchedPosts = querySearchMatchedPosts(parentIds, trimmedKeyword);
        Map<Id, FeedItem> feedItemById = new Map<Id, FeedItem>();
        List<SearchCandidate> candidates = new List<SearchCandidate>();

        for (FeedItem feedItem : matchedPosts) {
            feedItemById.put(feedItem.Id, feedItem);
            ParentRef parentRef = parentRefsById.get(feedItem.ParentId);
            if (parentRef == null) {
                continue;
            }
            candidates.add(buildPostSearchCandidate(feedItem, parentRef));
        }

        List<FeedComment> matchedComments = querySearchMatchedComments(parentIds, likePattern);
        Set<Id> missingFeedItemIds = new Set<Id>();
        for (FeedComment feedComment : matchedComments) {
            if (feedComment.FeedItemId != null && !feedItemById.containsKey(feedComment.FeedItemId)) {
                missingFeedItemIds.add(feedComment.FeedItemId);
            }
        }
        if (!missingFeedItemIds.isEmpty()) {
            for (FeedItem feedItem : queryFeedItemsByIds(missingFeedItemIds)) {
                feedItemById.put(feedItem.Id, feedItem);
            }
        }

        for (FeedComment feedComment : matchedComments) {
            FeedItem parentFeedItem = feedItemById.get(feedComment.FeedItemId);
            if (parentFeedItem == null) {
                continue;
            }

            ParentRef parentRef = parentRefsById.get(parentFeedItem.ParentId);
            if (parentRef == null) {
                continue;
            }

            candidates.add(buildCommentSearchCandidate(feedComment, parentFeedItem, parentRef));
        }

        candidates.addAll(queryAttachmentSearchCandidates(parentRefsById, trimmedKeyword));

        candidates.sort();

        List<ChatterSearchResultDTO> results = new List<ChatterSearchResultDTO>();
        Set<Id> addedFeedItemIds = new Set<Id>();
        for (SearchCandidate candidate : candidates) {
            if (candidate == null || candidate.feedItemId == null || addedFeedItemIds.contains(candidate.feedItemId)) {
                continue;
            }

            results.add(candidate.toDto());
            addedFeedItemIds.add(candidate.feedItemId);

            if (results.size() >= MAX_SEARCH_RESULTS) {
                break;
            }
        }

        return results;
    }

    private static List<FeedItem> querySearchMatchedPosts(Set<Id> parentIds, String keyword) {
        if (parentIds == null || parentIds.isEmpty()) {
            return new List<FeedItem>();
        }

        String normalizedKeyword = normalizeSearchText(keyword);
        if (String.isBlank(normalizedKeyword)) {
            return new List<FeedItem>();
        }

        List<FeedItem> matchedFeedItems = new List<FeedItem>();
        DateTime cursorDate;
        Id cursorFeedItemId;
        Integer scannedRows = 0;
        Integer batchSize = getPostBodySearchBatchSize();

        while (matchedFeedItems.size() < MAX_SEARCH_RESULTS && scannedRows < MAX_POST_BODY_SEARCH_ROWS) {
            Integer remainingRows = MAX_POST_BODY_SEARCH_ROWS - scannedRows;
            Integer currentBatchSize = batchSize < remainingRows ? batchSize : remainingRows;
            List<FeedItem> feedItems = querySearchFeedItemsBatch(parentIds, cursorDate, cursorFeedItemId, currentBatchSize);
            if (feedItems.isEmpty()) {
                break;
            }

            scannedRows += feedItems.size();
            for (FeedItem feedItem : feedItems) {
                if (normalizeSearchText(feedItem.Body).contains(normalizedKeyword)) {
                    matchedFeedItems.add(feedItem);
                    if (matchedFeedItems.size() >= MAX_SEARCH_RESULTS) {
                        break;
                    }
                }
            }

            FeedItem boundaryFeedItem = feedItems[feedItems.size() - 1];
            cursorDate = boundaryFeedItem.CreatedDate;
            cursorFeedItemId = boundaryFeedItem.Id;
            if (feedItems.size() < currentBatchSize) {
                break;
            }
        }

        return matchedFeedItems;
    }

    private static Integer getPostBodySearchBatchSize() {
        if (Test.isRunningTest()
            && postBodySearchBatchSizeOverrideForTest != null
            && postBodySearchBatchSizeOverrideForTest > 0) {
            return postBodySearchBatchSizeOverrideForTest;
        }
        return POST_BODY_SEARCH_BATCH_SIZE;
    }

    private static List<FeedItem> querySearchFeedItemsBatch(
        Set<Id> parentIds,
        DateTime cursorDate,
        Id cursorFeedItemId,
        Integer batchSize
    ) {
        if (parentIds == null || parentIds.isEmpty()) {
            return new List<FeedItem>();
        }

        Set<String> allowedFeedTypes = ALLOWED_FEED_TYPES;
        Integer queryLimit = batchSize == null || batchSize <= 0 ? POST_BODY_SEARCH_BATCH_SIZE : batchSize;
        String soql =
            'SELECT ' + String.join(buildFeedItemSelectedFields(false), ', ') +
            ' FROM FeedItem' +
            ' WHERE ParentId IN :parentIds' +
            ' AND Type IN :allowedFeedTypes';
        if (cursorDate != null && cursorFeedItemId != null) {
            soql += ' AND (CreatedDate > :cursorDate OR (CreatedDate = :cursorDate AND Id > :cursorFeedItemId))';
        }
        soql += ' ORDER BY CreatedDate ASC, Id ASC LIMIT :queryLimit';

        return Database.query(soql);
    }

    private static List<FeedComment> querySearchMatchedComments(Set<Id> parentIds, String likePattern) {
        if (parentIds == null || parentIds.isEmpty()) {
            return new List<FeedComment>();
        }

        Set<String> allowedFeedTypes = ALLOWED_FEED_TYPES;
        Integer queryLimit = MAX_SEARCH_RESULTS;
        String soql =
            'SELECT Id, FeedItemId, CreatedById, CreatedDate, CommentBody';
        if (canReadUserName()) {
            soql += ', CreatedBy.Name';
        }
        soql +=
            ' FROM FeedComment' +
            ' WHERE FeedItemId IN (' +
            '   SELECT Id FROM FeedItem WHERE ParentId IN :parentIds AND Type IN :allowedFeedTypes' +
            ' )' +
            ' AND CommentBody LIKE :likePattern' +
            ' ORDER BY CreatedDate ASC, Id ASC' +
            ' LIMIT :queryLimit';

        return Database.query(soql);
    }

    private static List<SearchCandidate> queryAttachmentSearchCandidates(
        Map<Id, ParentRef> parentRefsById,
        String keyword
    ) {
        List<SearchCandidate> candidates = new List<SearchCandidate>();
        if (parentRefsById == null || parentRefsById.isEmpty()) {
            return candidates;
        }

        String normalizedKeyword = normalizeSearchText(keyword);
        if (String.isBlank(normalizedKeyword)) {
            return candidates;
        }

        List<FeedItem> feedItems = queryAttachmentSearchFeedItems(parentRefsById.keySet());
        if (feedItems.isEmpty()) {
            return candidates;
        }

        CommentQueryResult commentQueryResult = queryCommentsForAttachmentSearch(feedItems);
        AttachmentQueryResult attachmentQueryResult = queryAttachmentsForPage(feedItems, commentQueryResult);
        Map<Id, FeedItem> feedItemById = new Map<Id, FeedItem>(feedItems);

        for (FeedItem feedItem : feedItems) {
            ParentRef parentRef = parentRefsById.get(feedItem.ParentId);
            if (parentRef == null) {
                continue;
            }
            addAttachmentMatchesForFeedItem(
                candidates,
                feedItem,
                parentRef,
                null,
                attachmentQueryResult.attachmentsByPostId.get(feedItem.Id),
                attachmentQueryResult.inlineImagesByPostId.get(feedItem.Id),
                normalizedKeyword
            );
        }

        for (Id feedItemId : commentQueryResult.commentsByFeedItemId.keySet()) {
            FeedItem parentFeedItem = feedItemById.get(feedItemId);
            if (parentFeedItem == null) {
                continue;
            }

            ParentRef parentRef = parentRefsById.get(parentFeedItem.ParentId);
            if (parentRef == null) {
                continue;
            }

            for (CommentDTO comment : commentQueryResult.commentsByFeedItemId.get(feedItemId)) {
                addAttachmentMatchesForFeedItem(
                    candidates,
                    parentFeedItem,
                    parentRef,
                    comment,
                    attachmentQueryResult.attachmentsByCommentId.get(comment.feedCommentId),
                    attachmentQueryResult.inlineImagesByCommentId.get(comment.feedCommentId),
                    normalizedKeyword
                );
            }
        }

        return candidates;
    }

    private static List<FeedItem> queryAttachmentSearchFeedItems(Set<Id> parentIds) {
        if (parentIds == null || parentIds.isEmpty()) {
            return new List<FeedItem>();
        }

        Set<String> allowedFeedTypes = ALLOWED_FEED_TYPES;
        Integer queryLimit = MAX_ATTACHMENT_SEARCH_FEED_ITEMS;
        List<String> selectedFields = buildFeedItemSelectedFields(false);

        String soql =
            'SELECT ' + String.join(selectedFields, ', ') +
            ' FROM FeedItem' +
            ' WHERE ParentId IN :parentIds' +
            ' AND Type IN :allowedFeedTypes' +
            ' ORDER BY CreatedDate DESC, Id DESC' +
            ' LIMIT :queryLimit';

        return Database.query(soql);
    }

    private static CommentQueryResult queryCommentsForAttachmentSearch(List<FeedItem> feedItems) {
        CommentQueryResult result = new CommentQueryResult();
        if (feedItems == null || feedItems.isEmpty()) {
            return result;
        }

        Set<Id> feedItemIds = new Set<Id>();
        for (FeedItem feedItem : feedItems) {
            feedItemIds.add(feedItem.Id);
        }

        String inlineImageLikePattern = '%' + INLINE_IMAGE_SRC_PREFIX + '%';
        String contentCommentType = COMMENT_TYPE_CONTENT_COMMENT;
        Integer queryLimit = MAX_ATTACHMENT_SEARCH_COMMENTS;
        String soql =
            'SELECT Id, FeedItemId, CreatedById, CreatedDate, CommentBody, RelatedRecordId, CommentType';
        if (canReadUserName()) {
            soql += ', CreatedBy.Name';
        }
        soql +=
            ' FROM FeedComment' +
            ' WHERE FeedItemId IN :feedItemIds' +
            ' AND (CommentType = :contentCommentType OR CommentBody LIKE :inlineImageLikePattern)' +
            ' ORDER BY CreatedDate ASC, Id ASC' +
            ' LIMIT :queryLimit';

        for (FeedComment feedComment : Database.query(soql)) {
            if (!result.commentsByFeedItemId.containsKey(feedComment.FeedItemId)) {
                result.commentsByFeedItemId.put(feedComment.FeedItemId, new List<CommentDTO>());
            }
            result.commentsByFeedItemId.get(feedComment.FeedItemId).add(toCommentDTO(feedComment));
        }
        return result;
    }

    private static List<FeedItem> queryFeedItemsByIds(Set<Id> feedItemIds) {
        if (feedItemIds == null || feedItemIds.isEmpty()) {
            return new List<FeedItem>();
        }

        List<String> selectedFields = buildFeedItemSelectedFields(false);

        String soql =
            'SELECT ' + String.join(selectedFields, ', ') +
            ' FROM FeedItem WHERE Id IN :feedItemIds';

        return Database.query(soql);
    }

    private static SearchCandidate buildPostSearchCandidate(FeedItem feedItem, ParentRef parentRef) {
        SearchCandidate candidate = new SearchCandidate();
        candidate.feedItemId = feedItem.Id;
        candidate.feedCommentId = null;
        candidate.previewText = buildSearchPreviewText(feedItem.Body);
        candidate.authorName = canReadUserName() && feedItem.CreatedBy != null ? feedItem.CreatedBy.Name : null;
        candidate.createdDate = feedItem.CreatedDate;
        candidate.originLabel = parentRef.originLabel;
        candidate.expandComments = false;
        candidate.sortId = feedItem.Id;
        candidate.sourcePriority = 0;
        return candidate;
    }

    private static SearchCandidate buildCommentSearchCandidate(
        FeedComment feedComment,
        FeedItem parentFeedItem,
        ParentRef parentRef
    ) {
        SearchCandidate candidate = new SearchCandidate();
        candidate.feedItemId = parentFeedItem.Id;
        candidate.feedCommentId = feedComment.Id;
        candidate.previewText = buildSearchPreviewText(feedComment.CommentBody);
        candidate.authorName = canReadUserName() && feedComment.CreatedBy != null ? feedComment.CreatedBy.Name : null;
        candidate.createdDate = feedComment.CreatedDate;
        candidate.originLabel = parentRef.originLabel;
        candidate.expandComments = true;
        candidate.sortId = feedComment.Id;
        candidate.sourcePriority = 1;
        return candidate;
    }

    private static void addAttachmentMatchesForFeedItem(
        List<SearchCandidate> candidates,
        FeedItem feedItem,
        ParentRef parentRef,
        CommentDTO comment,
        List<AttachmentDTO> attachments,
        List<InlineImageDTO> inlineImages,
        String normalizedKeyword
    ) {
        if (candidates == null
            || feedItem == null
            || parentRef == null
            || String.isBlank(normalizedKeyword)) {
            return;
        }

        Set<Id> seenContentDocumentIds = new Set<Id>();
        List<String> matchingFileNames = new List<String>();
        if (attachments != null) {
            for (AttachmentDTO attachment : attachments) {
                if (attachment == null || attachment.contentDocumentId == null) {
                    continue;
                }
                seenContentDocumentIds.add(attachment.contentDocumentId);
                String fileName = buildAttachmentDisplayName(attachment);
                if (normalizeSearchText(fileName).contains(normalizedKeyword)) {
                    matchingFileNames.add(fileName);
                }
            }
        }

        if (inlineImages != null) {
            for (InlineImageDTO inlineImage : inlineImages) {
                if (inlineImage == null || inlineImage.contentDocumentId == null) {
                    continue;
                }
                if (seenContentDocumentIds.contains(inlineImage.contentDocumentId)) {
                    continue;
                }
                seenContentDocumentIds.add(inlineImage.contentDocumentId);
                String fileName = buildAttachmentDisplayName(inlineImage);
                if (normalizeSearchText(fileName).contains(normalizedKeyword)) {
                    matchingFileNames.add(fileName);
                }
            }
        }

        if (matchingFileNames.isEmpty()) {
            return;
        }

        matchingFileNames.sort();
        candidates.add(buildAttachmentSearchCandidate(feedItem, parentRef, comment, matchingFileNames[0]));
    }

    private static SearchCandidate buildAttachmentSearchCandidate(
        FeedItem feedItem,
        ParentRef parentRef,
        CommentDTO comment,
        String fileName
    ) {
        SearchCandidate candidate = new SearchCandidate();
        candidate.feedItemId = feedItem.Id;
        candidate.feedCommentId = comment == null ? null : comment.feedCommentId;
        candidate.previewText = 'Arquivo: ' + fileName;
        candidate.authorName = comment == null
            ? (canReadUserName() && feedItem.CreatedBy != null ? feedItem.CreatedBy.Name : null)
            : comment.authorName;
        candidate.createdDate = comment == null ? feedItem.CreatedDate : comment.createdAt;
        candidate.originLabel = parentRef.originLabel;
        candidate.expandComments = comment != null;
        candidate.sortId = comment == null ? feedItem.Id : comment.feedCommentId;
        candidate.sourcePriority = 2;
        return candidate;
    }

    private static String buildAttachmentDisplayName(AttachmentDTO attachment) {
        return attachment == null
            ? buildAttachmentFileName(null, null)
            : buildAttachmentFileName(attachment.title, attachment.extension);
    }

    private static String buildAttachmentDisplayName(InlineImageDTO inlineImage) {
        return inlineImage == null
            ? buildAttachmentFileName(null, null)
            : buildAttachmentFileName(inlineImage.title, inlineImage.extension);
    }

    private static String buildSearchPreviewText(String value) {
        String sanitizedValue = String.valueOf(value == null ? '' : value);
        if (String.isBlank(sanitizedValue)) {
            return '';
        }

        return sanitizedValue
            .replaceAll('(?i)<br\\s*/?>', ' ')
            .replaceAll('(?i)</p>', ' ')
            .replaceAll('(?i)<[^>]+>', ' ')
            .replace('&nbsp;', ' ')
            .replaceAll('\\s+', ' ')
            .trim();
    }

    @TestVisible
    private static String normalizeSearchText(String value) {
        return removeSearchDiacritics(buildSearchPreviewText(value).toLowerCase());
    }

    private static String removeSearchDiacritics(String value) {
        if (String.isBlank(value)) {
            return '';
        }

        return value
            .replace('á', 'a').replace('à', 'a').replace('â', 'a').replace('ã', 'a').replace('ä', 'a')
            .replace('é', 'e').replace('è', 'e').replace('ê', 'e').replace('ë', 'e')
            .replace('í', 'i').replace('ì', 'i').replace('î', 'i').replace('ï', 'i')
            .replace('ó', 'o').replace('ò', 'o').replace('ô', 'o').replace('õ', 'o').replace('ö', 'o')
            .replace('ú', 'u').replace('ù', 'u').replace('û', 'u').replace('ü', 'u')
            .replace('ç', 'c').replace('ñ', 'n');
    }

    private static String escapeLikeKeyword(String keyword) {
        return keyword
            .replace('\\', '\\\\')
            .replace('%', '\\%')
            .replace('_', '\\_');
    }

    private static CommentQueryResult queryCommentsForPage(List<FeedItem> feedItems) {
        CommentQueryResult result = new CommentQueryResult();
        if (feedItems == null || feedItems.isEmpty()) {
            return result;
        }

        Set<Id> feedItemIds = new Set<Id>();
        for (FeedItem feedItem : feedItems) {
            feedItemIds.add(feedItem.Id);
        }

        Integer queryLimit = MAX_COMMENTS_PER_PAGE + 1;
        String soql =
            'SELECT Id, FeedItemId, CreatedById, CreatedDate, CommentBody, RelatedRecordId, CommentType';
        if (canReadUserName()) {
            soql += ', CreatedBy.Name';
        }
        soql +=
            ' FROM FeedComment' +
            ' WHERE FeedItemId IN :feedItemIds' +
            ' ORDER BY CreatedDate ASC, Id ASC' +
            ' LIMIT :queryLimit';

        List<FeedComment> feedComments = Database.query(soql);
        if (feedComments.size() > MAX_COMMENTS_PER_PAGE) {
            result.commentsTruncated = true;
            feedComments.remove(feedComments.size() - 1);
        }

        for (FeedComment feedComment : feedComments) {
            if (!feedItemIds.contains(feedComment.FeedItemId)) {
                continue;
            }
            if (!result.commentsByFeedItemId.containsKey(feedComment.FeedItemId)) {
                result.commentsByFeedItemId.put(feedComment.FeedItemId, new List<CommentDTO>());
            }
            result.commentsByFeedItemId.get(feedComment.FeedItemId).add(toCommentDTO(feedComment));
        }
        return result;
    }

    private static Map<Id, String> resolveAuthorPhotoUrls(
        List<FeedItem> feedItems,
        CommentQueryResult commentQueryResult
    ) {
        Map<Id, String> authorPhotoUrlByUserId = new Map<Id, String>();
        if (!canReadUserPhoto()) {
            return authorPhotoUrlByUserId;
        }

        Set<Id> authorIds = new Set<Id>();
        for (FeedItem feedItem : feedItems) {
            if (feedItem.CreatedById != null) {
                authorIds.add(feedItem.CreatedById);
            }
        }

        if (commentQueryResult != null) {
            for (List<CommentDTO> comments : commentQueryResult.commentsByFeedItemId.values()) {
                for (CommentDTO comment : comments) {
                    if (comment.authorId != null) {
                        authorIds.add(comment.authorId);
                    }
                }
            }
        }

        if (authorIds.isEmpty()) {
            return authorPhotoUrlByUserId;
        }

        for (User userRecord : [
            SELECT Id, SmallPhotoUrl
            FROM User
            WHERE Id IN :authorIds
        ]) {
            authorPhotoUrlByUserId.put(userRecord.Id, userRecord.SmallPhotoUrl);
        }
        return authorPhotoUrlByUserId;
    }

    private static AttachmentQueryResult queryAttachmentsForPage(
        List<FeedItem> feedItems,
        CommentQueryResult commentQueryResult
    ) {
        AttachmentReferenceMaps referenceMaps = collectAttachmentReferences(feedItems, commentQueryResult);
        return resolveAttachmentsForReferenceMaps(referenceMaps);
    }

    private static AttachmentReferenceMaps collectAttachmentReferences(
        List<FeedItem> feedItems,
        CommentQueryResult commentQueryResult
    ) {
        AttachmentReferenceMaps referenceMaps = new AttachmentReferenceMaps();
        if (feedItems == null || feedItems.isEmpty()) {
            return referenceMaps;
        }

        Set<Id> feedItemIds = new Set<Id>();
        for (FeedItem feedItem : feedItems) {
            feedItemIds.add(feedItem.Id);
        }

        for (FeedAttachment attachment : queryFeedAttachments(feedItemIds)) {
            addAttachmentRecordId(referenceMaps.recordIdsByPostId, attachment.FeedEntityId, attachment.RecordId);
        }

        for (FeedItem feedItem : feedItems) {
            addInlineImageReferences(referenceMaps.inlineImageRefsByPostId, feedItem.Id, feedItem.Body);
        }

        if (commentQueryResult != null) {
            for (List<CommentDTO> comments : commentQueryResult.commentsByFeedItemId.values()) {
                for (CommentDTO comment : comments) {
                    if (comment.commentType == COMMENT_TYPE_CONTENT_COMMENT && comment.relatedRecordId != null) {
                        addAttachmentRecordId(
                            referenceMaps.recordIdsByCommentId,
                            comment.feedCommentId,
                            comment.relatedRecordId
                        );
                    }
                    addInlineImageReferences(referenceMaps.inlineImageRefsByCommentId, comment.feedCommentId, comment.bodyText);
                }
            }
        }
        return referenceMaps;
    }

    private static void addAttachmentRecordId(Map<Id, List<Id>> recordIdsByOwnerId, Id ownerId, Id recordId) {
        if (ownerId == null || recordId == null) {
            return;
        }
        if (!recordIdsByOwnerId.containsKey(ownerId)) {
            recordIdsByOwnerId.put(ownerId, new List<Id>());
        }
        recordIdsByOwnerId.get(ownerId).add(recordId);
    }

    private static List<FeedAttachment> queryFeedAttachments(Set<Id> feedEntityIds) {
        if (feedEntityIds == null || feedEntityIds.isEmpty()) {
            return new List<FeedAttachment>();
        }

        return [
            SELECT Id, FeedEntityId, RecordId, Type
            FROM FeedAttachment
            WHERE FeedEntityId IN :feedEntityIds
            AND RecordId != null
        ];
    }

    private static void addInlineImageReferences(
        Map<Id, List<InlineImageReference>> inlineImageRefsByOwnerId,
        Id ownerId,
        String bodyText
    ) {
        if (ownerId == null || String.isBlank(bodyText) || !bodyText.toLowerCase().contains(INLINE_IMAGE_SRC_PREFIX)) {
            return;
        }

        Matcher imageTagMatcher = Pattern.compile('(?i)<img\\b[^>]*>').matcher(bodyText);
        Integer imageIndex = 0;
        while (imageTagMatcher.find()) {
            String imageTag = imageTagMatcher.group(0);
            Id contentDocumentId = parseInlineImageContentDocumentId(extractHtmlAttributeValue(imageTag, 'src'));
            if (contentDocumentId == null) {
                continue;
            }

            InlineImageReference reference = new InlineImageReference();
            reference.contentDocumentId = contentDocumentId;
            reference.altText = normalizeInlineImageAltText(extractHtmlAttributeValue(imageTag, 'alt'));
            reference.position = imageIndex;
            if (!inlineImageRefsByOwnerId.containsKey(ownerId)) {
                inlineImageRefsByOwnerId.put(ownerId, new List<InlineImageReference>());
            }
            inlineImageRefsByOwnerId.get(ownerId).add(reference);
            imageIndex++;
        }
    }

    private static Id parseInlineImageContentDocumentId(String srcValue) {
        String normalizedSrc = String.isBlank(srcValue) ? '' : srcValue.trim();
        if (!normalizedSrc.toLowerCase().startsWith(INLINE_IMAGE_SRC_PREFIX)) {
            return null;
        }

        String rawId = normalizedSrc.substring(INLINE_IMAGE_SRC_PREFIX.length());
        String candidate = readLeadingSalesforceId(rawId);
        if (String.isBlank(candidate)) {
            return null;
        }

        try {
            Id candidateId = (Id) candidate;
            return candidateId.getSObjectType() == ContentDocument.SObjectType ? candidateId : null;
        } catch (Exception ex) {
            return null;
        }
    }

    private static String readLeadingSalesforceId(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        String candidate = '';
        for (Integer index = 0; index < value.length(); index++) {
            String currentChar = value.substring(index, index + 1);
            if (!isAsciiAlphaNumeric(currentChar)) {
                break;
            }
            candidate += currentChar;
        }

        return candidate.length() == 15 || candidate.length() == 18 ? candidate : null;
    }

    private static Boolean isAsciiAlphaNumeric(String value) {
        return String.isNotBlank(value) && SALESFORCE_ID_CHARS.contains(value);
    }

    private static String extractHtmlAttributeValue(String htmlTag, String attributeName) {
        if (String.isBlank(htmlTag) || String.isBlank(attributeName)) {
            return null;
        }

        String lowerTag = htmlTag.toLowerCase();
        String lowerAttribute = attributeName.toLowerCase();
        Integer searchFrom = 0;
        while (searchFrom < lowerTag.length()) {
            Integer attributeIndex = lowerTag.indexOf(lowerAttribute, searchFrom);
            if (attributeIndex < 0) {
                return null;
            }
            if (attributeIndex > 0 && isHtmlNameCharacter(lowerTag.substring(attributeIndex - 1, attributeIndex))) {
                searchFrom = attributeIndex + lowerAttribute.length();
                continue;
            }

            Integer cursor = attributeIndex + lowerAttribute.length();
            cursor = skipWhitespace(htmlTag, cursor);
            if (cursor >= htmlTag.length() || htmlTag.substring(cursor, cursor + 1) != '=') {
                searchFrom = cursor;
                continue;
            }
            cursor = skipWhitespace(htmlTag, cursor + 1);
            if (cursor >= htmlTag.length()) {
                return null;
            }

            String quote = htmlTag.substring(cursor, cursor + 1);
            if (quote == '"' || quote == '\'') {
                Integer endQuote = htmlTag.indexOf(quote, cursor + 1);
                return endQuote < 0 ? null : htmlTag.substring(cursor + 1, endQuote);
            }

            Integer endIndex = cursor;
            while (endIndex < htmlTag.length()) {
                String currentChar = htmlTag.substring(endIndex, endIndex + 1);
                if (isWhitespace(currentChar) || currentChar == '>') {
                    break;
                }
                endIndex++;
            }
            return htmlTag.substring(cursor, endIndex);
        }
        return null;
    }

    private static Integer skipWhitespace(String value, Integer startIndex) {
        Integer cursor = startIndex;
        while (cursor < value.length() && isWhitespace(value.substring(cursor, cursor + 1))) {
            cursor++;
        }
        return cursor;
    }

    private static Boolean isWhitespace(String value) {
        return value == ' ' || value == '\n' || value == '\r' || value == '\t';
    }

    private static Boolean isHtmlNameCharacter(String value) {
        return isAsciiAlphaNumeric(value) || value == '-' || value == '_' || value == ':';
    }

    private static String normalizeInlineImageAltText(String altText) {
        String normalizedAltText = String.isBlank(altText) ? '' : altText.trim();
        return normalizedAltText.length() > 255 ? normalizedAltText.substring(0, 255) : normalizedAltText;
    }

    private static AttachmentQueryResult resolveAttachmentsForReferenceMaps(AttachmentReferenceMaps referenceMaps) {
        AttachmentQueryResult result = new AttachmentQueryResult();
        if (referenceMaps == null || referenceMaps.isEmpty()) {
            return result;
        }

        AttachmentResolutionInput resolutionInput = buildAttachmentResolutionInput(referenceMaps);
        if (resolutionInput.contentVersionIds.isEmpty() && resolutionInput.contentDocumentIds.isEmpty()) {
            return result;
        }

        Map<Id, AttachmentDTO> attachmentsByReferenceId = queryAccessibleAttachmentsByReferenceId(resolutionInput);
        applyResolvedAttachments(result.attachmentsByPostId, referenceMaps.recordIdsByPostId, attachmentsByReferenceId);
        applyResolvedAttachments(
            result.attachmentsByCommentId,
            referenceMaps.recordIdsByCommentId,
            attachmentsByReferenceId
        );
        applyResolvedInlineImages(result.inlineImagesByPostId, referenceMaps.inlineImageRefsByPostId, attachmentsByReferenceId);
        applyResolvedInlineImages(
            result.inlineImagesByCommentId,
            referenceMaps.inlineImageRefsByCommentId,
            attachmentsByReferenceId
        );
        return result;
    }

    @TestVisible
    private static Map<String, List<AttachmentDTO>> resolveAttachmentsForTest(
        Map<Id, List<Id>> recordIdsByPostId,
        Map<Id, List<Id>> recordIdsByCommentId
    ) {
        AttachmentReferenceMaps referenceMaps = new AttachmentReferenceMaps();
        if (recordIdsByPostId != null) {
            referenceMaps.recordIdsByPostId.putAll(recordIdsByPostId);
        }
        if (recordIdsByCommentId != null) {
            referenceMaps.recordIdsByCommentId.putAll(recordIdsByCommentId);
        }

        AttachmentQueryResult result = resolveAttachmentsForReferenceMaps(referenceMaps);
        Map<String, List<AttachmentDTO>> attachmentsByOwnerKey = new Map<String, List<AttachmentDTO>>();
        for (Id postId : result.attachmentsByPostId.keySet()) {
            attachmentsByOwnerKey.put('post:' + String.valueOf(postId), result.attachmentsByPostId.get(postId));
        }
        for (Id commentId : result.attachmentsByCommentId.keySet()) {
            attachmentsByOwnerKey.put('comment:' + String.valueOf(commentId), result.attachmentsByCommentId.get(commentId));
        }
        return attachmentsByOwnerKey;
    }

    @TestVisible
    private static Map<String, List<InlineImageDTO>> resolveInlineImagesForTest(
        Map<Id, String> bodyByPostId,
        Map<Id, String> bodyByCommentId
    ) {
        AttachmentReferenceMaps referenceMaps = new AttachmentReferenceMaps();
        if (bodyByPostId != null) {
            for (Id postId : bodyByPostId.keySet()) {
                addInlineImageReferences(referenceMaps.inlineImageRefsByPostId, postId, bodyByPostId.get(postId));
            }
        }
        if (bodyByCommentId != null) {
            for (Id commentId : bodyByCommentId.keySet()) {
                addInlineImageReferences(referenceMaps.inlineImageRefsByCommentId, commentId, bodyByCommentId.get(commentId));
            }
        }

        AttachmentQueryResult result = resolveAttachmentsForReferenceMaps(referenceMaps);
        Map<String, List<InlineImageDTO>> inlineImagesByOwnerKey = new Map<String, List<InlineImageDTO>>();
        for (Id postId : result.inlineImagesByPostId.keySet()) {
            inlineImagesByOwnerKey.put('post:' + String.valueOf(postId), result.inlineImagesByPostId.get(postId));
        }
        for (Id commentId : result.inlineImagesByCommentId.keySet()) {
            inlineImagesByOwnerKey.put('comment:' + String.valueOf(commentId), result.inlineImagesByCommentId.get(commentId));
        }
        return inlineImagesByOwnerKey;
    }

    private static AttachmentResolutionInput buildAttachmentResolutionInput(AttachmentReferenceMaps referenceMaps) {
        AttachmentResolutionInput input = new AttachmentResolutionInput();
        collectResolvableIds(referenceMaps.recordIdsByPostId, input);
        collectResolvableIds(referenceMaps.recordIdsByCommentId, input);
        collectInlineImageContentDocumentIds(referenceMaps.inlineImageRefsByPostId, input);
        collectInlineImageContentDocumentIds(referenceMaps.inlineImageRefsByCommentId, input);
        return input;
    }

    private static void collectResolvableIds(Map<Id, List<Id>> recordIdsByOwnerId, AttachmentResolutionInput input) {
        for (List<Id> recordIds : recordIdsByOwnerId.values()) {
            for (Id recordId : recordIds) {
                Schema.SObjectType referencedType = recordId.getSObjectType();
                if (referencedType == ContentVersion.SObjectType) {
                    input.contentVersionIds.add(recordId);
                } else if (referencedType == ContentDocument.SObjectType) {
                    input.contentDocumentIds.add(recordId);
                }
            }
        }
    }

    private static void collectInlineImageContentDocumentIds(
        Map<Id, List<InlineImageReference>> inlineImageRefsByOwnerId,
        AttachmentResolutionInput input
    ) {
        for (List<InlineImageReference> references : inlineImageRefsByOwnerId.values()) {
            for (InlineImageReference reference : references) {
                if (reference.contentDocumentId != null) {
                    input.contentDocumentIds.add(reference.contentDocumentId);
                }
            }
        }
    }

    private static Map<Id, AttachmentDTO> queryAccessibleAttachmentsByReferenceId(AttachmentResolutionInput input) {
        Map<Id, AttachmentDTO> attachmentsByReferenceId = new Map<Id, AttachmentDTO>();
        String selectedFields = buildContentVersionSelectClause();

        if (!input.contentVersionIds.isEmpty()) {
            Set<Id> contentVersionIds = new Set<Id>(input.contentVersionIds);
            String contentVersionSoql =
                'SELECT ' + selectedFields +
                ' FROM ContentVersion' +
                ' WHERE Id IN :contentVersionIds';
            for (ContentVersion version : Database.query(contentVersionSoql)) {
                AttachmentDTO attachment = toAttachmentDTO(version);
                if (attachment != null) {
                    attachmentsByReferenceId.put(version.Id, attachment);
                }
            }
        }

        if (!input.contentDocumentIds.isEmpty()) {
            Set<Id> contentDocumentIds = new Set<Id>(input.contentDocumentIds);
            String contentDocumentSoql =
                'SELECT ' + selectedFields +
                ' FROM ContentVersion' +
                ' WHERE ContentDocumentId IN :contentDocumentIds' +
                ' AND IsLatest = true';
            for (ContentVersion version : Database.query(contentDocumentSoql)) {
                AttachmentDTO attachment = toAttachmentDTO(version);
                if (attachment != null) {
                    attachmentsByReferenceId.put(version.ContentDocumentId, attachment);
                }
            }
        }
        return attachmentsByReferenceId;
    }

    private static String buildContentVersionSelectClause() {
        return String.join(new List<String>{
            'Id',
            'ContentDocumentId',
            'Title',
            'FileExtension',
            'ContentSize',
            'FileType',
            'IsLatest'
        }, ', ');
    }

    private static void applyResolvedAttachments(
        Map<Id, List<AttachmentDTO>> attachmentsByOwnerId,
        Map<Id, List<Id>> recordIdsByOwnerId,
        Map<Id, AttachmentDTO> attachmentsByReferenceId
    ) {
        for (Id ownerId : recordIdsByOwnerId.keySet()) {
            Set<String> seenStableKeys = new Set<String>();
            for (Id recordId : recordIdsByOwnerId.get(ownerId)) {
                AttachmentDTO attachment = attachmentsByReferenceId.get(recordId);
                if (attachment == null || seenStableKeys.contains(attachment.stableKey)) {
                    continue;
                }
                if (!attachmentsByOwnerId.containsKey(ownerId)) {
                    attachmentsByOwnerId.put(ownerId, new List<AttachmentDTO>());
                }
                attachmentsByOwnerId.get(ownerId).add(attachment);
                seenStableKeys.add(attachment.stableKey);
            }
        }
    }

    private static void applyResolvedInlineImages(
        Map<Id, List<InlineImageDTO>> inlineImagesByOwnerId,
        Map<Id, List<InlineImageReference>> inlineImageRefsByOwnerId,
        Map<Id, AttachmentDTO> attachmentsByReferenceId
    ) {
        for (Id ownerId : inlineImageRefsByOwnerId.keySet()) {
            Integer renderedIndex = 0;
            for (InlineImageReference reference : inlineImageRefsByOwnerId.get(ownerId)) {
                AttachmentDTO attachment = attachmentsByReferenceId.get(reference.contentDocumentId);
                InlineImageDTO inlineImage = toInlineImageDTO(reference, attachment, renderedIndex);
                if (inlineImage == null) {
                    continue;
                }
                if (!inlineImagesByOwnerId.containsKey(ownerId)) {
                    inlineImagesByOwnerId.put(ownerId, new List<InlineImageDTO>());
                }
                inlineImagesByOwnerId.get(ownerId).add(inlineImage);
                renderedIndex++;
            }
        }
    }

    private static AttachmentDTO toAttachmentDTO(ContentVersion version) {
        if (version == null || version.Id == null || version.ContentDocumentId == null) {
            return null;
        }

        AttachmentDTO attachment = new AttachmentDTO();
        attachment.contentDocumentId = version.ContentDocumentId;
        attachment.contentVersionId = version.Id;
        attachment.title = version.Title;
        attachment.extension = String.isBlank(version.FileExtension)
            ? null
            : version.FileExtension.toLowerCase();
        attachment.size = version.ContentSize;
        attachment.fileType = version.FileType;
        attachment.isImage = isImageFile(version.FileType, version.FileExtension);
        attachment.stableKey = String.valueOf(version.ContentDocumentId) + ':' + String.valueOf(version.Id);
        return attachment;
    }

    private static InlineImageDTO toInlineImageDTO(
        InlineImageReference reference,
        AttachmentDTO attachment,
        Integer renderedIndex
    ) {
        if (reference == null
            || attachment == null
            || attachment.isImage != true
            || attachment.contentDocumentId == null
            || attachment.contentVersionId == null) {
            return null;
        }

        InlineImageDTO inlineImage = new InlineImageDTO();
        inlineImage.contentDocumentId = attachment.contentDocumentId;
        inlineImage.contentVersionId = attachment.contentVersionId;
        inlineImage.title = attachment.title;
        inlineImage.extension = attachment.extension;
        inlineImage.size = attachment.size;
        inlineImage.fileType = attachment.fileType;
        inlineImage.isImage = true;
        inlineImage.altText = reference.altText;
        inlineImage.stableKey = String.valueOf(attachment.contentDocumentId) + ':inline:' + String.valueOf(renderedIndex);
        return inlineImage;
    }

    private static Boolean isImageFile(String fileType, String extension) {
        String normalizedFileType = String.isBlank(fileType) ? null : fileType.trim().toUpperCase();
        if (normalizedFileType != null && IMAGE_FILE_TYPES.contains(normalizedFileType)) {
            return true;
        }

        String normalizedExtension = String.isBlank(extension) ? null : extension.trim().toLowerCase();
        return normalizedExtension != null && IMAGE_EXTENSIONS.contains(normalizedExtension);
    }

    private static Boolean shouldReturnPost(PostDTO post) {
        return post != null
            && (String.isNotBlank(post.bodyText)
                || !post.attachments.isEmpty()
                || (post.feedType == FEED_TYPE_LINK_POST
                    ? String.isNotBlank(post.linkUrl)
                    : post.feedType != FEED_TYPE_CONTENT_POST));
    }

    private static Boolean shouldReturnComment(CommentDTO comment) {
        return comment != null
            && (String.isNotBlank(comment.bodyText)
                || !comment.attachments.isEmpty()
                || comment.commentType != COMMENT_TYPE_CONTENT_COMMENT);
    }

    @TestVisible
    private static Boolean shouldReturnContentPostForTest(String bodyText, Boolean hasResolvedAttachment) {
        PostDTO post = new PostDTO();
        post.bodyText = bodyText;
        post.feedType = FEED_TYPE_CONTENT_POST;
        if (hasResolvedAttachment == true) {
            post.attachments.add(new AttachmentDTO());
        }
        return shouldReturnPost(post);
    }

    @TestVisible
    private static Boolean shouldReturnLinkPostForTest(String bodyText, String linkUrl) {
        PostDTO post = new PostDTO();
        post.bodyText = bodyText;
        post.feedType = FEED_TYPE_LINK_POST;
        post.linkUrl = linkUrl;
        return shouldReturnPost(post);
    }

    @TestVisible
    private static Boolean shouldReturnContentCommentForTest(String bodyText, Boolean hasResolvedAttachment) {
        CommentDTO comment = new CommentDTO();
        comment.bodyText = bodyText;
        comment.commentType = COMMENT_TYPE_CONTENT_COMMENT;
        if (hasResolvedAttachment == true) {
            comment.attachments.add(new AttachmentDTO());
        }
        return shouldReturnComment(comment);
    }

    private static Boolean canReadUserName() {
        return isObjectReadable(User.SObjectType)
            && isFieldReadable(User.SObjectType, 'Name');
    }

    private static Boolean canReadUserPhoto() {
        return isObjectReadable(User.SObjectType)
            && isFieldReadable(User.SObjectType, 'SmallPhotoUrl');
    }

    private static PostDTO toPostDTO(FeedItem feedItem, ParentRef parentRef) {
        PostDTO post = new PostDTO();
        post.feedItemId = feedItem.Id;
        post.originRecordId = parentRef == null ? null : parentRef.recordId;
        post.originObjectApiName = parentRef == null ? null : parentRef.objectApiName;
        post.originLabel = parentRef == null ? 'Registro relacionado' : parentRef.originLabel;
        post.authorId = feedItem.CreatedById;
        post.authorName = canReadUserName()
            ? toSafeAuthorName(getRelationshipFieldStringValue(feedItem, 'CreatedBy', 'Name'))
            : null;
        post.createdDate = feedItem.CreatedDate;
        post.bodyText = feedItem.Body;
        post.feedType = feedItem.Type;
        post.linkUrl = getFeedItemStringValue(feedItem, 'LinkUrl');
        post.linkTitle = getFeedItemStringValue(feedItem, 'Title');
        post.renderKey = String.valueOf(feedItem.Id);
        return post;
    }

    private static String getFeedItemStringValue(FeedItem feedItem, String fieldApiName) {
        if (feedItem == null || String.isBlank(fieldApiName)) {
            return null;
        }

        Map<String, Object> populatedFields = feedItem.getPopulatedFieldsAsMap();
        if (!populatedFields.containsKey(fieldApiName)) {
            return null;
        }

        Object rawValue = populatedFields.get(fieldApiName);
        return rawValue == null ? null : String.valueOf(rawValue);
    }

    private static String getContentVersionStringValue(ContentVersion version, String fieldApiName) {
        if (version == null || String.isBlank(fieldApiName)) {
            return null;
        }

        Map<String, Object> populatedFields = version.getPopulatedFieldsAsMap();
        if (!populatedFields.containsKey(fieldApiName)) {
            return null;
        }

        Object rawValue = populatedFields.get(fieldApiName);
        return rawValue == null ? null : String.valueOf(rawValue);
    }

    private static String getRelationshipFieldStringValue(SObject recordData, String relationshipApiName, String fieldApiName) {
        if (recordData == null || String.isBlank(relationshipApiName) || String.isBlank(fieldApiName)) {
            return null;
        }

        SObject relatedRecord = recordData.getSObject(relationshipApiName);
        if (relatedRecord == null) {
            return null;
        }

        Object rawValue = relatedRecord.get(fieldApiName);
        return rawValue == null ? null : String.valueOf(rawValue);
    }

    private static CommentDTO toCommentDTO(FeedComment feedComment) {
        CommentDTO comment = new CommentDTO();
        comment.feedCommentId = feedComment.Id;
        comment.feedItemId = feedComment.FeedItemId;
        comment.authorId = feedComment.CreatedById;
        comment.authorName = canReadUserName()
            ? toSafeAuthorName(getRelationshipFieldStringValue(feedComment, 'CreatedBy', 'Name'))
            : 'Usuario do Chatter';
        comment.createdAt = feedComment.CreatedDate;
        comment.bodyText = feedComment.CommentBody;
        comment.stableKey = String.valueOf(feedComment.Id);
        comment.relatedRecordId = feedComment.RelatedRecordId;
        comment.commentType = feedComment.CommentType;
        return comment;
    }

    private static String toSafeAuthorName(String authorName) {
        return String.isBlank(authorName) ? 'Usuario do Chatter' : authorName;
    }

    private static Id resolveAttachmentContentDocumentId(String contentDocumentId, String contentVersionId) {
        Id documentId = tryParseContentDocumentId(contentDocumentId);
        if (documentId != null) {
            return documentId;
        }

        Id versionId = tryParseContentVersionId(contentVersionId);
        if (versionId == null) {
            throw new ChatterHistoryException(ERROR_INACCESSIBLE_ATTACHMENT);
        }
        return queryContentDocumentIdForVersion(versionId);
    }

    private static Id queryContentDocumentIdForVersion(Id versionId) {
        List<ContentVersion> versions = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :versionId
            LIMIT 1
        ];
        Id contentDocumentId = versions.isEmpty() ? null : versions[0].ContentDocumentId;
        if (contentDocumentId == null) {
            throw new ChatterHistoryException(ERROR_INACCESSIBLE_ATTACHMENT);
        }
        return contentDocumentId;
    }

    private static Id tryParseContentDocumentId(String rawId) {
        if (String.isBlank(rawId)) {
            return null;
        }
        try {
            Id parsedId = (Id) rawId;
            return String.valueOf(parsedId).startsWith('069') ? parsedId : null;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Id tryParseContentVersionId(String rawId) {
        if (String.isBlank(rawId)) {
            return null;
        }
        try {
            Id parsedId = (Id) rawId;
            return String.valueOf(parsedId).startsWith('068') ? parsedId : null;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Boolean isAuthorizedAttachmentForExpandedHistory(
        Id contentDocumentId,
        Set<Id> allowedParentIds,
        Id feedItemId,
        Id feedCommentId
    ) {
        if (contentDocumentId == null || allowedParentIds == null || allowedParentIds.isEmpty()) {
            return false;
        }

        if (feedCommentId != null) {
            return isAuthorizedCommentAttachment(contentDocumentId, allowedParentIds, feedItemId, feedCommentId);
        }
        if (feedItemId != null) {
            return isAuthorizedPostAttachment(contentDocumentId, allowedParentIds, feedItemId);
        }
        return false;
    }

    private static Boolean isAuthorizedPostAttachment(
        Id contentDocumentId,
        Set<Id> allowedParentIds,
        Id feedItemId
    ) {
        FeedItem feedItem = queryFeedItemForAttachment(feedItemId);
        if (feedItem == null || !allowedParentIds.contains(feedItem.ParentId)) {
            return false;
        }

        if (bodyContainsInlineImageDocument(feedItem.Body, contentDocumentId)) {
            return true;
        }
        if (isDocumentLinkedToEntity(contentDocumentId, feedItemId)) {
            return true;
        }
        return isDocumentReferencedByFeedAttachments(feedItemId, contentDocumentId);
    }

    private static Boolean isAuthorizedCommentAttachment(
        Id contentDocumentId,
        Set<Id> allowedParentIds,
        Id expectedFeedItemId,
        Id feedCommentId
    ) {
        FeedComment feedComment = queryFeedCommentForAttachment(feedCommentId);
        if (feedComment == null) {
            return false;
        }
        if (expectedFeedItemId != null && feedComment.FeedItemId != expectedFeedItemId) {
            return false;
        }

        FeedItem parentFeedItem = queryFeedItemForAttachment(feedComment.FeedItemId);
        if (parentFeedItem == null || !allowedParentIds.contains(parentFeedItem.ParentId)) {
            return false;
        }

        if (bodyContainsInlineImageDocument(feedComment.CommentBody, contentDocumentId)) {
            return true;
        }
        if (feedComment.CommentType == COMMENT_TYPE_CONTENT_COMMENT
            && isResolvedReferenceDocument(feedComment.RelatedRecordId, contentDocumentId)) {
            return true;
        }
        return isDocumentLinkedToEntity(contentDocumentId, feedCommentId);
    }

    private static FeedItem queryFeedItemForAttachment(Id feedItemId) {
        if (feedItemId == null) {
            return null;
        }

        List<FeedItem> feedItems = [
            SELECT Id, ParentId, Body
            FROM FeedItem
            WHERE Id = :feedItemId
            LIMIT 1
        ];
        return feedItems.isEmpty() ? null : feedItems[0];
    }

    private static FeedComment queryFeedCommentForAttachment(Id feedCommentId) {
        if (feedCommentId == null) {
            return null;
        }

        List<FeedComment> feedComments = [
            SELECT Id, FeedItemId, CommentBody, RelatedRecordId, CommentType
            FROM FeedComment
            WHERE Id = :feedCommentId
            LIMIT 1
        ];
        return feedComments.isEmpty() ? null : feedComments[0];
    }

    private static Boolean bodyContainsInlineImageDocument(String bodyText, Id contentDocumentId) {
        if (contentDocumentId == null || String.isBlank(bodyText) || !bodyText.toLowerCase().contains(INLINE_IMAGE_SRC_PREFIX)) {
            return false;
        }

        Matcher imageTagMatcher = Pattern.compile('(?i)<img\\b[^>]*>').matcher(bodyText);
        while (imageTagMatcher.find()) {
            Id inlineContentDocumentId = parseInlineImageContentDocumentId(
                extractHtmlAttributeValue(imageTagMatcher.group(0), 'src')
            );
            if (inlineContentDocumentId == contentDocumentId) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isResolvedReferenceDocument(Id recordId, Id expectedContentDocumentId) {
        if (recordId == null || expectedContentDocumentId == null) {
            return false;
        }
        if (recordId.getSObjectType() == ContentDocument.SObjectType) {
            return recordId == expectedContentDocumentId;
        }
        if (recordId.getSObjectType() == ContentVersion.SObjectType) {
            return resolveAttachmentContentDocumentId(null, String.valueOf(recordId)) == expectedContentDocumentId;
        }
        return false;
    }

    private static Boolean isDocumentReferencedByFeedAttachments(Id feedItemId, Id expectedContentDocumentId) {
        if (feedItemId == null || expectedContentDocumentId == null) {
            return false;
        }

        AttachmentResolutionInput input = new AttachmentResolutionInput();
        for (FeedAttachment attachment : queryFeedAttachments(new Set<Id>{ feedItemId })) {
            Schema.SObjectType recordType = attachment.RecordId.getSObjectType();
            if (recordType == ContentVersion.SObjectType) {
                input.contentVersionIds.add(attachment.RecordId);
            } else if (recordType == ContentDocument.SObjectType) {
                input.contentDocumentIds.add(attachment.RecordId);
            }
        }

        if (input.contentVersionIds.isEmpty() && input.contentDocumentIds.isEmpty()) {
            return false;
        }

        Map<Id, AttachmentDTO> attachmentsByReferenceId = queryAccessibleAttachmentsByReferenceId(input);
        for (AttachmentDTO attachment : attachmentsByReferenceId.values()) {
            if (attachment != null && attachment.contentDocumentId == expectedContentDocumentId) {
                return true;
            }
        }
        return false;
    }

    private static Boolean isDocumentLinkedToEntity(Id contentDocumentId, Id linkedEntityId) {
        if (contentDocumentId == null || linkedEntityId == null) {
            return false;
        }

        Integer linkCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
            AND LinkedEntityId = :linkedEntityId
        ];
        return linkCount > 0;
    }

    private static ContentVersion queryAttachmentBinaryVersion(Id contentDocumentId) {
        List<ContentVersion> versions = [
            SELECT Id, Title, FileType, FileExtension, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];
        ContentVersion version = versions.isEmpty() ? null : versions[0];
        if (version == null || version.VersionData == null) {
            throw new ChatterHistoryException(ERROR_INACCESSIBLE_ATTACHMENT);
        }
        return version;
    }

    private static CommunicatorDTOs.AttachmentFileDTO buildAttachmentFileDto(ContentVersion version) {
        CommunicatorDTOs.AttachmentFileDTO dto = new CommunicatorDTOs.AttachmentFileDTO();
        dto.fileName = buildAttachmentFileName(version.Title, version.FileExtension);
        dto.contentType = String.isNotBlank(version.FileType) ? version.FileType : 'UNKNOWN';
        dto.fileExtension = String.isNotBlank(version.FileExtension) ? version.FileExtension : '';
        dto.base64Data = EncodingUtil.base64Encode(version.VersionData);
        return dto;
    }

    private static String buildAttachmentFileName(String title, String extension) {
        String normalizedTitle = String.isBlank(title) ? 'arquivo' : title.trim();
        String normalizedExtension = String.isBlank(extension) ? '' : extension.trim();
        if (String.isBlank(normalizedExtension)) {
            return normalizedTitle;
        }

        String suffix = '.' + normalizedExtension;
        return normalizedTitle.toLowerCase().endsWith(suffix.toLowerCase())
            ? normalizedTitle
            : normalizedTitle + suffix;
    }

    public class ChatterHistoryPageDTO {
        @AuraEnabled public List<PostDTO> posts;
        @AuraEnabled public String previousPageCursor;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public Integer returnedCount;
        @AuraEnabled public Boolean commentsTruncated;

        public ChatterHistoryPageDTO() {
            posts = new List<PostDTO>();
            hasMore = false;
            returnedCount = 0;
            commentsTruncated = false;
        }
    }

    public class PostDTO {
        @AuraEnabled public Id feedItemId;
        @AuraEnabled public Id originRecordId;
        @AuraEnabled public String originObjectApiName;
        @AuraEnabled public String originLabel;
        @AuraEnabled public Id authorId;
        @AuraEnabled public String authorName;
        @AuraEnabled public String authorPhotoUrl;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public String bodyText;
        @AuraEnabled public String feedType;
        @AuraEnabled public String linkUrl;
        @AuraEnabled public String linkTitle;
        @AuraEnabled public String renderKey;
        @AuraEnabled public List<CommentDTO> comments;
        @AuraEnabled public List<AttachmentDTO> attachments;
        @AuraEnabled public List<InlineImageDTO> inlineImages;

        public PostDTO() {
            comments = new List<CommentDTO>();
            attachments = new List<AttachmentDTO>();
            inlineImages = new List<InlineImageDTO>();
        }
    }

    public class ChatterSearchResultDTO {
        @AuraEnabled public Id feedItemId;
        @AuraEnabled public Id feedCommentId;
        @AuraEnabled public String previewText;
        @AuraEnabled public String authorName;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public String originLabel;
        @AuraEnabled public Boolean expandComments;
    }

    public class CommentDTO {
        @AuraEnabled public Id feedCommentId;
        @AuraEnabled public Id feedItemId;
        @AuraEnabled public Id authorId;
        @AuraEnabled public String authorName;
        @AuraEnabled public String authorPhotoUrl;
        @AuraEnabled public DateTime createdAt;
        @AuraEnabled public String bodyText;
        @AuraEnabled public String stableKey;
        @AuraEnabled public List<AttachmentDTO> attachments;
        @AuraEnabled public List<InlineImageDTO> inlineImages;
        private Id relatedRecordId;
        private String commentType;

        public CommentDTO() {
            attachments = new List<AttachmentDTO>();
            inlineImages = new List<InlineImageDTO>();
        }
    }

    public class InlineImageDTO {
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public String title;
        @AuraEnabled public String extension;
        @AuraEnabled public Integer size;
        @AuraEnabled public String fileType;
        @AuraEnabled public Boolean isImage;
        @AuraEnabled public String altText;
        @AuraEnabled public String stableKey;
    }

    public class AttachmentDTO implements Comparable {
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public String title;
        @AuraEnabled public String extension;
        @AuraEnabled public Integer size;
        @AuraEnabled public String fileType;
        @AuraEnabled public Boolean isImage;
        @AuraEnabled public String stableKey;

        public Integer compareTo(Object otherObject) {
            AttachmentDTO other = (AttachmentDTO) otherObject;
            Integer titleCompare = compareNullableStrings(normalizeSortValue(title), normalizeSortValue(other.title));
            if (titleCompare != 0) {
                return titleCompare;
            }
            return compareNullableStrings(String.valueOf(contentDocumentId), String.valueOf(other.contentDocumentId));
        }

        private String normalizeSortValue(String value) {
            return String.isBlank(value) ? '' : value.trim().toLowerCase();
        }

        private Integer compareNullableStrings(String leftValue, String rightValue) {
            String left = leftValue == null ? '' : leftValue;
            String right = rightValue == null ? '' : rightValue;
            return left.compareTo(right);
        }
    }

    private class ParentRef {
        private Id recordId;
        private String objectApiName;
        private String originLabel;
    }

    private class CursorState {
        public String opportunityId;
        public DateTime createdDate;
        public Id feedItemId;
        public String direction;
    }

    private class CommentQueryResult {
        private Map<Id, List<CommentDTO>> commentsByFeedItemId;
        private Boolean commentsTruncated;

        private CommentQueryResult() {
            commentsByFeedItemId = new Map<Id, List<CommentDTO>>();
            commentsTruncated = false;
        }
    }

    private class SearchCandidate implements Comparable {
        private Id feedItemId;
        private Id feedCommentId;
        private String previewText;
        private String authorName;
        private DateTime createdDate;
        private String originLabel;
        private Boolean expandComments;
        private Id sortId;
        private Integer sourcePriority;

        public Integer compareTo(Object otherRecord) {
            SearchCandidate other = (SearchCandidate) otherRecord;
            if (other == null) {
                return 1;
            }

            Long thisTime = createdDate == null ? 0 : createdDate.getTime();
            Long otherTime = other.createdDate == null ? 0 : other.createdDate.getTime();
            if (thisTime != otherTime) {
                return thisTime < otherTime ? -1 : 1;
            }

            Integer thisPriority = sourcePriority == null ? 0 : sourcePriority;
            Integer otherPriority = other.sourcePriority == null ? 0 : other.sourcePriority;
            if (thisPriority != otherPriority) {
                return thisPriority < otherPriority ? -1 : 1;
            }

            String thisId = String.valueOf(sortId == null ? '' : sortId);
            String otherId = String.valueOf(other.sortId == null ? '' : other.sortId);
            return thisId.compareTo(otherId);
        }

        private ChatterSearchResultDTO toDto() {
            ChatterSearchResultDTO dto = new ChatterSearchResultDTO();
            dto.feedItemId = feedItemId;
            dto.feedCommentId = feedCommentId;
            dto.previewText = previewText;
            dto.authorName = authorName;
            dto.createdDate = createdDate;
            dto.originLabel = originLabel;
            dto.expandComments = expandComments == true;
            return dto;
        }
    }

    private class AttachmentReferenceMaps {
        private Map<Id, List<Id>> recordIdsByPostId;
        private Map<Id, List<Id>> recordIdsByCommentId;
        private Map<Id, List<InlineImageReference>> inlineImageRefsByPostId;
        private Map<Id, List<InlineImageReference>> inlineImageRefsByCommentId;

        private AttachmentReferenceMaps() {
            recordIdsByPostId = new Map<Id, List<Id>>();
            recordIdsByCommentId = new Map<Id, List<Id>>();
            inlineImageRefsByPostId = new Map<Id, List<InlineImageReference>>();
            inlineImageRefsByCommentId = new Map<Id, List<InlineImageReference>>();
        }

        private Boolean isEmpty() {
            return recordIdsByPostId.isEmpty()
                && recordIdsByCommentId.isEmpty()
                && inlineImageRefsByPostId.isEmpty()
                && inlineImageRefsByCommentId.isEmpty();
        }
    }

    private class InlineImageReference {
        private Id contentDocumentId;
        private String altText;
        private Integer position;
    }

    private class AttachmentResolutionInput {
        private Set<Id> contentVersionIds;
        private Set<Id> contentDocumentIds;

        private AttachmentResolutionInput() {
            contentVersionIds = new Set<Id>();
            contentDocumentIds = new Set<Id>();
        }
    }

    private class AttachmentQueryResult {
        private Map<Id, List<AttachmentDTO>> attachmentsByPostId;
        private Map<Id, List<AttachmentDTO>> attachmentsByCommentId;
        private Map<Id, List<InlineImageDTO>> inlineImagesByPostId;
        private Map<Id, List<InlineImageDTO>> inlineImagesByCommentId;

        private AttachmentQueryResult() {
            attachmentsByPostId = new Map<Id, List<AttachmentDTO>>();
            attachmentsByCommentId = new Map<Id, List<AttachmentDTO>>();
            inlineImagesByPostId = new Map<Id, List<InlineImageDTO>>();
            inlineImagesByCommentId = new Map<Id, List<InlineImageDTO>>();
        }
    }

    private class ChatterHistoryException extends Exception {}
}