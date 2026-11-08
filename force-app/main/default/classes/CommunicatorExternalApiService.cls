public without sharing class CommunicatorExternalApiService {

    private static final Set<String> CONVERSATION_SORT_FIELDS =
        new Set<String>{ 'lastMessageAt', 'recordName', 'currentStage', 'unreadCount' };
    private static final Set<String> MESSAGE_SORT_FIELDS =
        new Set<String>{ 'sentAt' };
    private static final Set<String> GROUP_SORT_FIELDS =
        new Set<String>{ 'name', 'memberCount', 'lastActivityAt', 'unreadCount' };
    private static final Set<String> CONVERSATION_VIEW_MODES =
        new Set<String>{ 'thread', 'threadstage', 'opportunity' };
    private static final Set<String> CONVERSATION_FILTERS =
        new Set<String>{ 'all', 'read', 'unread' };
    @TestVisible private static Map<Id, Set<Id>> testBroadcastRecipientsByGroup;

    public static CommunicatorExternalApiDTOs.ApiResponseDTO searchRecords(Map<String, String> params) {
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(params.get('userId'));
        CommunicatorExternalApiAccessService.assertObjectRead(context, 'Opportunity');
        String keyword = params.get('q');
        if (String.isBlank(keyword)) {
            throw CommunicatorExternalApiErrorService.badRequest(
                'SEARCH_KEYWORD_REQUIRED',
                'q e obrigatorio.'
            );
        }

        Boolean paginate = hasPagination(params);
        Integer pageSize = toInteger(params.get('pageSize'));
        Integer pageNumber = toInteger(params.get('pageNumber'));
        Integer normalizedPageSize = CommunicatorExternalApiPaginationService.normalizePageSize(pageSize);
        Integer normalizedPageNumber = CommunicatorExternalApiPaginationService.normalizePageNumber(pageNumber);
        Integer offsetValue = CommunicatorExternalApiPaginationService.calculateOffset(pageSize, pageNumber);

        List<CommunicatorExternalApiDTOs.RecordSearchItemDTO> items =
            new List<CommunicatorExternalApiDTOs.RecordSearchItemDTO>();
        Set<Id> matchedOpportunityIds = queryAccessibleOpportunityIdsByKeyword(context, keyword);
        List<Opportunity> opportunities = matchedOpportunityIds.isEmpty()
            ? new List<Opportunity>()
            : [
                SELECT Id, Name, StageName
                FROM Opportunity
                WHERE Id IN :matchedOpportunityIds
                ORDER BY LastModifiedDate DESC
                LIMIT :normalizedPageSize
                OFFSET :offsetValue
            ];

        Map<Id, Repasse__c> latestRepasseByOpportunityId =
            CommunicatorRepasseService.getLatestRepassesByOpportunityIds(
                new Map<Id, Opportunity>(opportunities).keySet()
            );
        Set<Id> opportunityIdsWithThread = getOpportunityIdsWithExistingThread(
            new Map<Id, Opportunity>(opportunities).keySet()
        );

        for (Opportunity opportunityRecord : opportunities) {
            CommunicatorExternalApiDTOs.RecordSearchItemDTO item =
                new CommunicatorExternalApiDTOs.RecordSearchItemDTO();
            item.recordId = String.valueOf(opportunityRecord.Id);
            item.recordName = opportunityRecord.Name;
            item.recordObjectApiName = 'Opportunity';
            item.opportunityId = String.valueOf(opportunityRecord.Id);
            item.opportunityName = opportunityRecord.Name;
            item.currentStage = resolveCurrentStageForOpportunity(
                opportunityRecord,
                latestRepasseByOpportunityId.get(opportunityRecord.Id)
            );
            item.hasThread = opportunityIdsWithThread.contains(opportunityRecord.Id);
            Repasse__c repasseRecord = latestRepasseByOpportunityId.get(opportunityRecord.Id);
            if (repasseRecord != null) {
                item.repasseId = String.valueOf(repasseRecord.Id);
                item.repasseName = repasseRecord.Name;
            }
            items.add(item);
        }

        CommunicatorExternalApiDTOs.ApiResponseDTO response = successResponse(items, context.timezoneSidKey);
        response.page = CommunicatorExternalApiPaginationService.buildPage(
            normalizedPageSize,
            normalizedPageNumber,
            matchedOpportunityIds.size(),
            null
        );
        return response;
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO getListConversations(Map<String, String> params) {
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(params.get('userId'));
        CommunicatorExternalApiAccessService.assertObjectRead(context, 'CommunicatorThread__c');
        Boolean paginate = hasPagination(params);
        Integer pageSize = toInteger(params.get('pageSize'));
        Integer pageNumber = toInteger(params.get('pageNumber'));
        Integer normalizedPageSize = CommunicatorExternalApiPaginationService.normalizePageSize(pageSize);
        Integer normalizedPageNumber = CommunicatorExternalApiPaginationService.normalizePageNumber(pageNumber);
        Integer offsetValue = CommunicatorExternalApiPaginationService.calculateOffset(pageSize, pageNumber);
        String keyword = params.get('q');
        String filter = String.isBlank(params.get('filter')) ? 'all' : params.get('filter').trim().toLowerCase();
        validateConversationFilter(filter);
        String viewMode = normalizeConversationViewMode(params.get('viewMode'));

        Set<Id> candidateThreadIds = new Set<Id>(context.accessibleThreadIds);
        removeGroupAndBroadcastThreads(candidateThreadIds);
        List<CommunicatorExternalApiDTOs.ConversationItemDTO> items =
            buildConversationItems(context, candidateThreadIds, keyword);
        items = applyConversationFilter(items, filter);
        items = applyConversationViewMode(items, viewMode);
        sortConversationItems(items, params.get('sortBy'), params.get('sortDirection'));

        Integer totalItems = items.size();
        if (paginate) {
            items = paginateConversationItems(items, normalizedPageSize, offsetValue);
        } else {
            CommunicatorExternalApiPaginationService.validateNonPaginatedLimit(
                totalItems,
                '/services/apexrest/comunicador/v1/conversations?userId=' +
                    String.valueOf(context.userId) + '&pageSize=50&pageNumber=1'
            );
        }

        CommunicatorExternalApiDTOs.ApiResponseDTO response = successResponse(items, context.timezoneSidKey);
        if (paginate) {
            response.page = CommunicatorExternalApiPaginationService.buildPage(
                normalizedPageSize,
                normalizedPageNumber,
                totalItems,
                null
            );
        }
        return response;
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO getListRecordThreads(
        String recordId,
        Map<String, String> params
    ) {
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(params.get('userId'));
        CommunicatorExternalApiAccessService.assertRecordAccess(context, recordId);
        CommunicatorExternalApiAccessService.assertObjectRead(context, 'CommunicatorThread__c');

        String normalizedRecordId = CommunicatorExternalApiAccessService.normalizeRecordId(recordId);
        List<CommunicatorThread__c> threads = [
            SELECT Id, Name, RecordId__c, RecordType__c, Stage__c, LastMessageAt__c, Status__c
            FROM CommunicatorThread__c
            WHERE RecordId__c = :normalizedRecordId
            AND Status__c != 'Archived'
            ORDER BY LastMessageAt__c DESC NULLS LAST, Id DESC
        ];

        CommunicatorExternalApiDTOs.RecordThreadsDTO result =
            new CommunicatorExternalApiDTOs.RecordThreadsDTO();
        if (threads.isEmpty()) {
            result.hasThread = false;
            result.status = 'NO_THREAD_CREATED';
            result.message = 'Nao possui thread criada para este contexto.';
            return successResponse(result, context.timezoneSidKey);
        }

        Set<Id> filteredThreadIds = CommunicatorExternalApiAccessService.filterThreadIds(
            context,
            new Map<Id, CommunicatorThread__c>(threads).keySet()
        );
        result.hasThread = !filteredThreadIds.isEmpty();
        if (!result.hasThread) {
            result.status = 'NO_THREAD_CREATED';
            result.message = 'Nao possui thread criada para este contexto.';
            return successResponse(result, context.timezoneSidKey);
        }

        result.threads = buildConversationItems(context, filteredThreadIds, null);
        sortConversationItems(result.threads, params.get('sortBy'), params.get('sortDirection'));
        return successResponse(result, context.timezoneSidKey);
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO getListRecordMessages(
        String recordId,
        Map<String, String> params
    ) {
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(params.get('userId'));
        CommunicatorExternalApiAccessService.assertRecordAccess(context, recordId);
        CommunicatorExternalApiAccessService.assertObjectRead(context, 'CommunicatorThread__c');
        CommunicatorExternalApiAccessService.assertObjectRead(context, 'CommunicatorMessage__c');

        Integer pageSize = toInteger(params.get('pageSize'));
        Integer pageNumber = toInteger(params.get('pageNumber'));
        Integer normalizedPageSize = CommunicatorExternalApiPaginationService.normalizePageSize(pageSize);
        Integer normalizedPageNumber = CommunicatorExternalApiPaginationService.normalizePageNumber(pageNumber);
        Integer offsetValue = CommunicatorExternalApiPaginationService.calculateOffset(pageSize, pageNumber);
        String direction = CommunicatorExternalApiSortService.normalizeDirection(params.get('sortDirection'));
        CommunicatorExternalApiSortService.validateSortField(params.get('sortBy'), MESSAGE_SORT_FIELDS, 'sentAt');

        String normalizedRecordId = CommunicatorExternalApiAccessService.normalizeRecordId(recordId);
        List<CommunicatorThread__c> threadRows = [
            SELECT Id
            FROM CommunicatorThread__c
            WHERE RecordId__c = :normalizedRecordId
            AND Status__c != 'Archived'
        ];
        Set<Id> threadIds = CommunicatorExternalApiAccessService.filterThreadIds(
            context,
            new Map<Id, CommunicatorThread__c>(threadRows).keySet()
        );
        Integer totalItems = threadIds.isEmpty() ? 0 : [
            SELECT COUNT()
            FROM CommunicatorMessage__c
            WHERE Thread__c IN :threadIds
        ];
        List<CommunicatorMessage__c> messages = threadIds.isEmpty()
            ? new List<CommunicatorMessage__c>()
            : queryRecordMessages(threadIds, normalizedPageSize, offsetValue, direction);

        CommunicatorExternalApiDTOs.ApiResponseDTO response =
            successResponse(mapMessages(context, messages), context.timezoneSidKey);
        response.page = CommunicatorExternalApiPaginationService.buildPage(
            normalizedPageSize,
            normalizedPageNumber,
            totalItems,
            null
        );
        return response;
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO getThreadChat(
        String threadId,
        Map<String, String> params
    ) {
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(params.get('userId'));
        Id typedThreadId = parseThreadId(threadId);
        CommunicatorExternalApiAccessService.assertThreadAccess(context, typedThreadId);
        CommunicatorExternalApiAccessService.assertObjectRead(context, 'CommunicatorMessage__c');
        CommunicatorExternalApiDTOs.ChatThreadDTO chat = buildThreadChat(
            context,
            typedThreadId,
            toInteger(params.get('pageSize')),
            toInteger(params.get('pageNumber'))
        );
        return successResponse(chat, context.timezoneSidKey);
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO getListThreadMessages(
        String threadId,
        Map<String, String> params
    ) {
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(params.get('userId'));
        Id typedThreadId = parseThreadId(threadId);
        CommunicatorExternalApiAccessService.assertThreadAccess(context, typedThreadId);
        CommunicatorExternalApiAccessService.assertObjectRead(context, 'CommunicatorMessage__c');

        Integer pageSize = toInteger(params.get('pageSize'));
        Integer pageNumber = toInteger(params.get('pageNumber'));
        Integer normalizedPageSize = CommunicatorExternalApiPaginationService.normalizePageSize(pageSize);
        Integer normalizedPageNumber = CommunicatorExternalApiPaginationService.normalizePageNumber(pageNumber);
        Integer offsetValue = CommunicatorExternalApiPaginationService.calculateOffset(pageSize, pageNumber);
        String direction = CommunicatorExternalApiSortService.normalizeDirection(params.get('sortDirection'));
        CommunicatorExternalApiSortService.validateSortField(params.get('sortBy'), MESSAGE_SORT_FIELDS, 'sentAt');

        Integer totalItems = [
            SELECT COUNT()
            FROM CommunicatorMessage__c
            WHERE Thread__c = :typedThreadId
        ];
        List<CommunicatorMessage__c> messages =
            queryThreadMessages(typedThreadId, normalizedPageSize, offsetValue, direction);

        List<CommunicatorExternalApiDTOs.MessageDTO> items = mapMessages(context, messages);
        CommunicatorExternalApiDTOs.ApiResponseDTO response = successResponse(items, context.timezoneSidKey);
        response.page = CommunicatorExternalApiPaginationService.buildPage(
            normalizedPageSize,
            normalizedPageNumber,
            totalItems,
            null
        );
        return response;
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO sendMessage(String requestBody) {
        CommunicatorExternalApiDTOs.SendMessageRequestDTO request =
            (CommunicatorExternalApiDTOs.SendMessageRequestDTO)
                JSON.deserialize(requestBody, CommunicatorExternalApiDTOs.SendMessageRequestDTO.class);
        if (request == null) {
            throw CommunicatorExternalApiErrorService.badRequest(
                'INVALID_BODY',
                'Body da requisicao invalido.'
            );
        }
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(request.userId);

        Id threadId;
        if (String.isNotBlank(request.threadId)) {
            threadId = parseThreadId(request.threadId);
            CommunicatorExternalApiAccessService.assertThreadAccess(context, threadId);
        } else {
            if (String.isBlank(request.recordId)) {
                throw CommunicatorExternalApiErrorService.badRequest(
                    'THREAD_OR_RECORD_REQUIRED',
                    'threadId ou recordId e obrigatorio.'
                );
            }
            CommunicatorExternalApiAccessService.assertRecordAccess(context, request.recordId);
            threadId = resolveOrCreateThreadForSend(request.recordId);
        }

        CommunicatorMessage__c createdMessage = createRepresentedMessage(
            context,
            threadId,
            request.body,
            request.mentionedUserIds,
            request.mentionedGroupIds,
            request.contentDocumentId,
            request.contentVersionId
        );
        return successResponse(mapMessages(context, new List<CommunicatorMessage__c>{ createdMessage })[0], context.timezoneSidKey);
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO setThreadAsRead(
        String threadId,
        String requestBody
    ) {
        CommunicatorExternalApiDTOs.SetReadRequestDTO request =
            (CommunicatorExternalApiDTOs.SetReadRequestDTO)
                JSON.deserialize(requestBody, CommunicatorExternalApiDTOs.SetReadRequestDTO.class);
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(request.userId);
        Id typedThreadId = parseThreadId(threadId);
        CommunicatorExternalApiAccessService.assertThreadAccess(context, typedThreadId);
        markThreadAsReadForUser(context.userId, typedThreadId, request.readAt);
        return successResponse('OK', context.timezoneSidKey);
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO getListNotifications(Map<String, String> params) {
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(params.get('userId'));
        Integer pageSize = toInteger(params.get('pageSize'));
        Integer pageNumber = toInteger(params.get('pageNumber'));
        Integer normalizedPageSize = CommunicatorExternalApiPaginationService.normalizePageSize(pageSize);
        Integer normalizedPageNumber = CommunicatorExternalApiPaginationService.normalizePageNumber(pageNumber);
        Integer offsetValue = CommunicatorExternalApiPaginationService.calculateOffset(pageSize, pageNumber);

        List<CommunicatorNotification__c> notifications = [
            SELECT Id, Name, Message__c, Message__r.Name, Thread__c, Thread__r.Name, Recipient__c,
                   Recipient__r.Name, Type__c, IsRead__c, ReadAt__c, CreatedDate, Thread__r.RecordId__c
            FROM CommunicatorNotification__c
            WHERE Recipient__c = :context.userId
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT :normalizedPageSize
            OFFSET :offsetValue
        ];
        List<CommunicatorExternalApiDTOs.NotificationItemDTO> items =
            mapNotifications(context, notifications);
        Integer totalItems = [
            SELECT COUNT()
            FROM CommunicatorNotification__c
            WHERE Recipient__c = :context.userId
        ];
        CommunicatorExternalApiDTOs.ApiResponseDTO response = successResponse(items, context.timezoneSidKey);
        response.page = CommunicatorExternalApiPaginationService.buildPage(
            normalizedPageSize,
            normalizedPageNumber,
            totalItems,
            null
        );
        return response;
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO getUnreadCount(Map<String, String> params) {
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(params.get('userId'));
        CommunicatorExternalApiDTOs.UnreadCountDTO dto = new CommunicatorExternalApiDTOs.UnreadCountDTO();
        dto.totalUnreadCount = [
            SELECT COUNT()
            FROM CommunicatorNotification__c
            WHERE Recipient__c = :context.userId
            AND IsRead__c = false
        ];
        dto.mentionUnreadCount = [
            SELECT COUNT()
            FROM CommunicatorNotification__c
            WHERE Recipient__c = :context.userId
            AND IsRead__c = false
            AND IsMention__c = true
        ];
        dto.broadcastUnreadCount = [
            SELECT COUNT()
            FROM CommunicatorNotification__c
            WHERE Recipient__c = :context.userId
            AND IsRead__c = false
            AND Type__c = 'Broadcast'
        ];
        dto.groupUnreadCount = 0;
        dto.threadId = params.get('threadId');
        dto.recordId = params.get('recordId');
        if (String.isNotBlank(dto.threadId)) {
            dto.threadUnreadCount = [
                SELECT COUNT()
                FROM CommunicatorNotification__c
                WHERE Recipient__c = :context.userId
                AND IsRead__c = false
                AND Thread__c = :parseThreadId(dto.threadId)
            ];
        }
        return successResponse(dto, context.timezoneSidKey);
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO getListGroups(Map<String, String> params) {
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(params.get('userId'));
        String type = String.isBlank(params.get('type')) ? 'all' : params.get('type').trim().toLowerCase();
        List<CommunicatorExternalApiDTOs.GroupItemDTO> items = new List<CommunicatorExternalApiDTOs.GroupItemDTO>();

        if (type == 'all' || type == 'standard') {
            items.addAll(loadConventionalGroups(context));
        }
        if (type == 'all' || type == 'broadcast') {
            items.addAll(loadBroadcastGroups(context));
        }

        sortGroupItems(items, params.get('sortBy'), params.get('sortDirection'));
        return buildListResponse(
            items,
            context,
            params,
            '/services/apexrest/comunicador/v1/groups?userId=' + String.valueOf(context.userId) +
                '&pageSize=50&pageNumber=1'
        );
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO getGroupDetail(
        String groupId,
        Map<String, String> params
    ) {
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(params.get('userId'));
        Id typedGroupId = parseGroupId(groupId);
        Boolean isBroadcast = context.broadcastGroupIds.contains(typedGroupId);
        if (!isBroadcast && !context.conventionalGroupIds.contains(typedGroupId)) {
            throw CommunicatorExternalApiErrorService.forbidden(
                'GROUP_ACCESS_DENIED',
                'Usuario informado nao possui acesso a este grupo.'
            );
        }

        CommunicatorExternalApiDTOs.GroupDetailDTO detail = new CommunicatorExternalApiDTOs.GroupDetailDTO();
        detail.groupInfo = isBroadcast
            ? loadBroadcastGroupItem(context, typedGroupId)
            : loadConventionalGroupItem(context, typedGroupId);
        detail.members = isBroadcast
            ? new List<CommunicatorExternalApiDTOs.ParticipantDTO>()
            : loadGroupMembers(typedGroupId);
        if (detail.groupInfo != null && String.isNotBlank(detail.groupInfo.threadId)) {
            detail.chat = buildThreadChat(
                context,
                parseThreadId(detail.groupInfo.threadId),
                toInteger(params.get('pageSize')),
                toInteger(params.get('pageNumber'))
            );
        }
        return successResponse(detail, context.timezoneSidKey);
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO getListGroupMembers(
        String groupId,
        Map<String, String> params
    ) {
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(params.get('userId'));
        Id typedGroupId = parseGroupId(groupId);
        if (!context.conventionalGroupIds.contains(typedGroupId)) {
            throw CommunicatorExternalApiErrorService.forbidden(
                'GROUP_ACCESS_DENIED',
                'Usuario informado nao possui acesso a este grupo.'
            );
        }
        return successResponse(loadGroupMembers(typedGroupId), context.timezoneSidKey);
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO createGroup(String requestBody) {
        CommunicatorExternalApiDTOs.GroupCreateRequestDTO request =
            (CommunicatorExternalApiDTOs.GroupCreateRequestDTO)
                JSON.deserialize(requestBody, CommunicatorExternalApiDTOs.GroupCreateRequestDTO.class);
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(request.userId);
        if (String.isBlank(request.name)) {
            throw CommunicatorExternalApiErrorService.badRequest(
                'GROUP_NAME_REQUIRED',
                'name e obrigatorio.'
            );
        }

        CommunicatorGroup__c groupRecord = new CommunicatorGroup__c(
            Name = request.name.trim(),
            Description__c = String.isBlank(request.description) ? null : request.description.trim(),
            IsActive__c = true,
            Type__c = 'Conventional',
            CreatedByUser__c = context.userId,
            MemberCount__c = 0
        );
        insert groupRecord;

        Set<Id> memberUserIds = toIdSet(request.memberUserIds, 'User');
        memberUserIds.add(context.userId);
        List<CommunicatorGroupMember__c> members = new List<CommunicatorGroupMember__c>();
        for (Id memberUserId : memberUserIds) {
            members.add(new CommunicatorGroupMember__c(Group__c = groupRecord.Id, User__c = memberUserId));
        }
        if (!members.isEmpty()) {
            insert members;
            CommunicatorGroupSharingService.ensureManualReadShares(groupRecord.Id, memberUserIds);
            update new CommunicatorGroup__c(Id = groupRecord.Id, MemberCount__c = memberUserIds.size());
        }

        CommunicatorExternalApiAccessService.clearCachedUserContext(context.userId);
        return successResponse(loadConventionalGroupItem(context, groupRecord.Id), context.timezoneSidKey);
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO setGroupUsers(
        String groupId,
        String requestBody
    ) {
        CommunicatorExternalApiDTOs.GroupUsersRequestDTO request =
            (CommunicatorExternalApiDTOs.GroupUsersRequestDTO)
                JSON.deserialize(requestBody, CommunicatorExternalApiDTOs.GroupUsersRequestDTO.class);
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(request.userId);
        Id typedGroupId = parseGroupId(groupId);
        if (!context.conventionalGroupIds.contains(typedGroupId)) {
            throw CommunicatorExternalApiErrorService.forbidden(
                'GROUP_ACCESS_DENIED',
                'Usuario informado nao possui acesso a este grupo.'
            );
        }

        Set<Id> usersToAdd = toIdSet(request.usersToAdd, 'User');
        Set<Id> usersToRemove = toIdSet(request.usersToRemove, 'User');
        for (Id userId : usersToAdd) {
            CommunicatorGroupService.addMember(typedGroupId, userId);
        }
        for (Id userId : usersToRemove) {
            CommunicatorGroupService.removeMember(typedGroupId, userId);
        }
        CommunicatorExternalApiAccessService.clearCachedUserContext(context.userId);
        return successResponse(loadConventionalGroupItem(context, typedGroupId), context.timezoneSidKey);
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO sendGroupMessage(
        String groupId,
        String requestBody
    ) {
        CommunicatorExternalApiDTOs.SendGroupMessageRequestDTO request =
            (CommunicatorExternalApiDTOs.SendGroupMessageRequestDTO)
                JSON.deserialize(requestBody, CommunicatorExternalApiDTOs.SendGroupMessageRequestDTO.class);
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(request.userId);
        Id typedGroupId = parseGroupId(groupId);
        if (!context.conventionalGroupIds.contains(typedGroupId) && !context.broadcastGroupIds.contains(typedGroupId)) {
            throw CommunicatorExternalApiErrorService.forbidden(
                'GROUP_ACCESS_DENIED',
                'Usuario informado nao possui acesso a este grupo.'
            );
        }

        CommunicatorThread__c threadRecord = CommunicatorThreadService.getOrCreateGroupThread(typedGroupId);
        CommunicatorMessage__c messageRecord = createRepresentedMessage(
            context,
            threadRecord.Id,
            request.body,
            request.mentionedUserIds,
            request.mentionedGroupIds,
            request.contentDocumentId,
            request.contentVersionId
        );
        return successResponse(mapMessages(context, new List<CommunicatorMessage__c>{ messageRecord })[0], context.timezoneSidKey);
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO getGroupChat(
        String groupId,
        Map<String, String> params
    ) {
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(params.get('userId'));
        Id typedGroupId = parseGroupId(groupId);
        if (!context.conventionalGroupIds.contains(typedGroupId) && !context.broadcastGroupIds.contains(typedGroupId)) {
            throw CommunicatorExternalApiErrorService.forbidden(
                'GROUP_ACCESS_DENIED',
                'Usuario informado nao possui acesso a este grupo.'
            );
        }
        Id threadId = findActiveGroupThreadId(typedGroupId, context.broadcastGroupIds.contains(typedGroupId));
        if (threadId == null) {
            return successResponse(buildEmptyGroupChat(context, typedGroupId), context.timezoneSidKey);
        }
        return successResponse(
            buildThreadChat(context, threadId, toInteger(params.get('pageSize')), toInteger(params.get('pageNumber'))),
            context.timezoneSidKey
        );
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO createBroadcastGroup(String requestBody) {
        CommunicatorExternalApiDTOs.BroadcastCreateRequestDTO request =
            (CommunicatorExternalApiDTOs.BroadcastCreateRequestDTO)
                JSON.deserialize(requestBody, CommunicatorExternalApiDTOs.BroadcastCreateRequestDTO.class);
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(request.userId);
        List<CommunicatorBroadcastAudience__c> audiences = new List<CommunicatorBroadcastAudience__c>();
        if (request.audiences != null) {
            for (CommunicatorExternalApiDTOs.BroadcastAudienceDTO audience : request.audiences) {
                audiences.add(new CommunicatorBroadcastAudience__c(
                    AudienceType__c = audience.audienceType,
                    TargetId__c = audience.targetId,
                    TargetName__c = audience.targetName,
                    SortOrder__c = audience.sortOrder
                ));
            }
        }
        CommunicatorGroup__c groupRecord = createRepresentedBroadcastGroup(context, request, audiences);
        return successResponse(loadBroadcastGroupItem(context, groupRecord.Id), context.timezoneSidKey);
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO sendBroadcast(String requestBody) {
        CommunicatorExternalApiDTOs.BroadcastSendRequestDTO request =
            (CommunicatorExternalApiDTOs.BroadcastSendRequestDTO)
                JSON.deserialize(requestBody, CommunicatorExternalApiDTOs.BroadcastSendRequestDTO.class);
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(request.userId);
        Id groupId = parseGroupId(request.groupId);
        if (!context.broadcastGroupIds.contains(groupId)) {
            throw CommunicatorExternalApiErrorService.forbidden(
                'BROADCAST_ACCESS_DENIED',
                'Usuario informado nao possui acesso a este comunicado.'
            );
        }
        List<Id> attachmentIds = new List<Id>();
        if (String.isNotBlank(request.contentDocumentId)) {
            attachmentIds.add(parseContentDocumentId(request.contentDocumentId));
        } else if (String.isNotBlank(request.contentVersionId)) {
            attachmentIds.add(resolveContentDocumentIdFromVersion(request.contentVersionId));
        }
        CommunicatorMessage__c messageRecord = createRepresentedBroadcastMessage(
            context,
            groupId,
            request.subject,
            request.body,
            attachmentIds
        );
        return successResponse(mapMessages(context, new List<CommunicatorMessage__c>{ messageRecord })[0], context.timezoneSidKey);
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO getListBroadcasts(Map<String, String> params) {
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(params.get('userId'));
        List<CommunicatorExternalApiDTOs.GroupItemDTO> items = loadBroadcastGroups(context);
        sortGroupItems(items, params.get('sortBy'), params.get('sortDirection'));
        return buildListResponse(
            items,
            context,
            params,
            '/services/apexrest/comunicador/v1/broadcasts?userId=' + String.valueOf(context.userId) +
                '&pageSize=50&pageNumber=1'
        );
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO getBroadcastDetail(
        String broadcastId,
        Map<String, String> params
    ) {
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(params.get('userId'));
        Id typedGroupId = parseGroupId(broadcastId);
        if (!context.broadcastGroupIds.contains(typedGroupId)) {
            throw CommunicatorExternalApiErrorService.forbidden(
                'BROADCAST_ACCESS_DENIED',
                'Usuario informado nao possui acesso a este comunicado.'
            );
        }
        CommunicatorExternalApiDTOs.BroadcastDetailDTO dto =
            new CommunicatorExternalApiDTOs.BroadcastDetailDTO();
        dto.broadcast = mapBroadcastGroupRecord(context, typedGroupId);
        dto.audiences = loadBroadcastAudiences(typedGroupId);
        Id threadId = dto.broadcast == null || String.isBlank(dto.broadcast.threadId)
            ? null
            : parseThreadId(dto.broadcast.threadId);
        if (threadId != null) {
            dto.messages = mapMessages(context, queryThreadMessages(
                threadId,
                CommunicatorExternalApiPaginationService.normalizePageSize(toInteger(params.get('pageSize'))),
                CommunicatorExternalApiPaginationService.calculateOffset(
                    toInteger(params.get('pageSize')),
                    toInteger(params.get('pageNumber'))
                ),
                'asc'
            ));
        } else {
            dto.messages = new List<CommunicatorExternalApiDTOs.MessageDTO>();
        }
        return successResponse(dto, context.timezoneSidKey);
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO setBroadcastAsRead(
        String broadcastId,
        String requestBody
    ) {
        CommunicatorExternalApiDTOs.SetReadRequestDTO request =
            (CommunicatorExternalApiDTOs.SetReadRequestDTO)
                JSON.deserialize(requestBody, CommunicatorExternalApiDTOs.SetReadRequestDTO.class);
        CommunicatorExternalApiDTOs.UserContextDTO context =
            CommunicatorExternalApiAccessService.requireUserContext(request.userId);
        Id typedGroupId = parseGroupId(broadcastId);
        if (!context.broadcastGroupIds.contains(typedGroupId)) {
            throw CommunicatorExternalApiErrorService.forbidden(
                'BROADCAST_ACCESS_DENIED',
                'Usuario informado nao possui acesso a este comunicado.'
            );
        }
        Id threadId = findActiveGroupThreadId(typedGroupId, true);
        if (threadId != null) {
            markThreadAsReadForUser(context.userId, threadId, request.readAt);
        }
        return successResponse('OK', context.timezoneSidKey);
    }

    private static CommunicatorExternalApiDTOs.ApiResponseDTO successResponse(Object data, String timezoneSidKey) {
        CommunicatorExternalApiDTOs.ApiResponseDTO response =
            new CommunicatorExternalApiDTOs.ApiResponseDTO();
        response.success = true;
        response.data = data;
        response.timezone = timezoneSidKey;
        return response;
    }

    private static Set<Id> queryAccessibleOpportunityIdsByKeyword(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        String keyword
    ) {
        String likeKeyword = '%' + keyword.trim() + '%';
        Set<Id> opportunityIds = new Set<Id>();
        Set<Id> scopedIds = new Set<Id>(context.accessibleOpportunityIds);
        Set<Id> approvalAnalysisIds = getAnaliseCreditoIdsByAprovacaoKeyword(likeKeyword);
        Id userId = context.userId;
        // Person Accounts may not be enabled in every org (for example, POC orgs).
        String cpfCondition = hasPersonAccountCpfField() ? ' OR Account.CPF__pc LIKE :likeKeyword' : '';
        if (context.isCoreSalesforce == true && scopedIds.isEmpty()) {
            String soql = 'SELECT Id FROM Opportunity WHERE OwnerId = :userId AND ('
                + 'Name LIKE :likeKeyword OR StageName LIKE :likeKeyword'
                + cpfCondition
                + ' OR AnaliseCredito__r.Name LIKE :likeKeyword OR AnaliseCredito__c IN :approvalAnalysisIds) LIMIT 500';
            for (SObject opportunityRecord : Database.query(soql)) {
                opportunityIds.add(opportunityRecord.Id);
            }
        } else {
            if (!scopedIds.isEmpty()) {
                String soql = 'SELECT Id FROM Opportunity WHERE Id IN :scopedIds AND ('
                    + 'Name LIKE :likeKeyword OR StageName LIKE :likeKeyword'
                    + cpfCondition
                    + ' OR AnaliseCredito__r.Name LIKE :likeKeyword OR AnaliseCredito__c IN :approvalAnalysisIds) LIMIT 500';
                for (SObject opportunityRecord : Database.query(soql)) {
                    opportunityIds.add(opportunityRecord.Id);
                }
            }
        }

        Set<Id> repasseOpportunityIds = CommunicatorRepasseService.getCandidateOpportunityIdsByKeyword(
            keyword,
            500,
            context.assessoriaIds == null || context.assessoriaIds.isEmpty() ? null : context.assessoriaIds
        );
        if (context.isCoreSalesforce != true) {
            repasseOpportunityIds.retainAll(context.accessibleOpportunityIds);
        }
        opportunityIds.addAll(repasseOpportunityIds);
        return opportunityIds;
    }

    private static Boolean hasPersonAccountCpfField() {
        for (String fieldName : Account.SObjectType.getDescribe().fields.getMap().keySet()) {
            if (fieldName.equalsIgnoreCase('CPF__pc')) return true;
        }
        return false;
    }

    private static Set<Id> getAnaliseCreditoIdsByAprovacaoKeyword(String likeKeyword) {
        Set<Id> analysisIds = new Set<Id>();
        if (String.isBlank(likeKeyword)) return analysisIds;
        for (AprovacaoBancaria__c approvalRecord : [
            SELECT AnaliseCredito__c
            FROM AprovacaoBancaria__c
            WHERE AnaliseCredito__c != null
            AND Name LIKE :likeKeyword
            LIMIT 500
        ]) {
            analysisIds.add(approvalRecord.AnaliseCredito__c);
        }
        return analysisIds;
    }

    private static Set<Id> getOpportunityIdsWithExistingThread(Set<Id> opportunityIds) {
        Set<Id> threadOpportunityIds = new Set<Id>();
        if (opportunityIds == null || opportunityIds.isEmpty()) return threadOpportunityIds;
        for (CommunicatorThread__c threadRecord : [
            SELECT RecordId__c
            FROM CommunicatorThread__c
            WHERE RecordId__c IN :opportunityIds
            AND Status__c != 'Archived'
        ]) {
            Id typedId = tryParseId(threadRecord.RecordId__c);
            if (typedId != null) {
                threadOpportunityIds.add(typedId);
            }
        }
        return threadOpportunityIds;
    }

    private static void removeGroupAndBroadcastThreads(Set<Id> threadIds) {
        if (threadIds == null || threadIds.isEmpty()) return;
        Set<Id> toRemove = new Set<Id>();
        for (CommunicatorThread__c threadRecord : [
            SELECT Id, RecordType__c
            FROM CommunicatorThread__c
            WHERE Id IN :threadIds
        ]) {
            if (threadRecord.RecordType__c == 'CommunicatorGroup__c') {
                toRemove.add(threadRecord.Id);
            }
        }
        threadIds.removeAll(toRemove);
    }

    private static List<CommunicatorExternalApiDTOs.ConversationItemDTO> buildConversationItems(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        Set<Id> threadIds,
        String keyword
    ) {
        List<CommunicatorExternalApiDTOs.ConversationItemDTO> items =
            new List<CommunicatorExternalApiDTOs.ConversationItemDTO>();
        if (threadIds == null || threadIds.isEmpty()) return items;

        Map<Id, Integer> unreadByThread = loadUnreadByThread(context.userId, threadIds);
        Map<Id, CommunicatorMessage__c> lastMessageByThread = loadLastMessageByThread(threadIds);
        Set<Id> opportunityIds = new Set<Id>();
        Map<Id, CommunicatorThread__c> threadById = new Map<Id, CommunicatorThread__c>();
        for (CommunicatorThread__c threadRecord : [
            SELECT Id, Name, RecordId__c, RecordType__c, Stage__c, LastMessageAt__c, Status__c
            FROM CommunicatorThread__c
            WHERE Id IN :threadIds
            ORDER BY LastMessageAt__c DESC NULLS LAST, Id DESC
        ]) {
            threadById.put(threadRecord.Id, threadRecord);
            Id opportunityId = tryParseId(threadRecord.RecordId__c);
            if (opportunityId != null && threadRecord.RecordType__c == 'Opportunity') {
                opportunityIds.add(opportunityId);
            }
        }

        Map<Id, Opportunity> opportunityById = opportunityIds.isEmpty()
            ? new Map<Id, Opportunity>()
            : new Map<Id, Opportunity>([
                SELECT Id, Name, StageName
                FROM Opportunity
                WHERE Id IN :opportunityIds
            ]);
        Map<Id, Repasse__c> latestRepasseByOpportunityId =
            CommunicatorRepasseService.getLatestRepassesByOpportunityIds(opportunityIds);

        for (CommunicatorThread__c threadRecord : threadById.values()) {
            Id opportunityId = threadRecord.RecordType__c == 'Opportunity'
                ? tryParseId(threadRecord.RecordId__c)
                : tryParseId(CommunicatorThreadService.resolveOpportunityIdIfRepasse(threadRecord.RecordId__c));
            Opportunity opportunityRecord = opportunityById.get(opportunityId);
            Repasse__c repasseRecord = latestRepasseByOpportunityId.get(opportunityId);
            CommunicatorMessage__c lastMessage = lastMessageByThread.get(threadRecord.Id);
            CommunicatorExternalApiDTOs.ConversationItemDTO item =
                new CommunicatorExternalApiDTOs.ConversationItemDTO();
            item.threadId = String.valueOf(threadRecord.Id);
            item.threadName = threadRecord.Name;
            item.recordId = threadRecord.RecordId__c;
            item.recordObjectApiName = threadRecord.RecordType__c;
            item.opportunityId = opportunityId == null ? null : String.valueOf(opportunityId);
            item.opportunityName = opportunityRecord == null ? null : opportunityRecord.Name;
            item.recordName = opportunityRecord == null ? null : opportunityRecord.Name;
            item.currentStage = resolveCurrentStageForOpportunity(opportunityRecord, repasseRecord);
            item.stage = threadRecord.Stage__c;
            item.lastMessageAt = CommunicatorExternalApiDateTimeService.formatForUser(
                threadRecord.LastMessageAt__c,
                context.timezoneSidKey
            );
            item.unreadCount = unreadByThread.containsKey(threadRecord.Id) ? unreadByThread.get(threadRecord.Id) : 0;
            item.isRead = item.unreadCount == 0;
            if (repasseRecord != null) {
                item.repasseId = String.valueOf(repasseRecord.Id);
                item.repasseName = repasseRecord.Name;
            }
            if (lastMessage != null) {
                item.lastMessageBody = canReadMessageField(context, 'Body__c') ? lastMessage.Body__c : null;
                item.lastSenderId = canReadMessageField(context, 'Sender__c') && lastMessage.Sender__c != null
                    ? String.valueOf(lastMessage.Sender__c)
                    : null;
                item.lastSenderName = item.lastSenderId == null || lastMessage.Sender__r == null
                    ? null
                    : lastMessage.Sender__r.Name;
            }
            item.hasThread = true;
            item.viewMode = 'thread';
            if (matchesConversationKeyword(item, keyword)) {
                items.add(item);
            }
        }
        return items;
    }

    private static Boolean matchesConversationKeyword(
        CommunicatorExternalApiDTOs.ConversationItemDTO item,
        String keyword
    ) {
        if (String.isBlank(keyword) || item == null) return true;
        String loweredKeyword = keyword.trim().toLowerCase();
        return containsIgnoreCase(item.recordName, loweredKeyword) ||
            containsIgnoreCase(item.currentStage, loweredKeyword) ||
            containsIgnoreCase(item.repasseName, loweredKeyword) ||
            containsIgnoreCase(item.lastMessageBody, loweredKeyword);
    }

    private static Boolean containsIgnoreCase(String value, String loweredKeyword) {
        return String.isNotBlank(value) && value.toLowerCase().contains(loweredKeyword);
    }

    private static Map<Id, Integer> loadUnreadByThread(Id userId, Set<Id> threadIds) {
        Map<Id, Integer> unreadByThread = new Map<Id, Integer>();
        if (threadIds == null || threadIds.isEmpty()) return unreadByThread;
        for (AggregateResult row : [
            SELECT Thread__c threadId, COUNT(Id) unreadCount
            FROM CommunicatorNotification__c
            WHERE Recipient__c = :userId
            AND IsRead__c = false
            AND Thread__c IN :threadIds
            GROUP BY Thread__c
        ]) {
            unreadByThread.put((Id) row.get('threadId'), Integer.valueOf(row.get('unreadCount')));
        }
        return unreadByThread;
    }

    private static Map<Id, CommunicatorMessage__c> loadLastMessageByThread(Set<Id> threadIds) {
        Map<Id, CommunicatorMessage__c> result = new Map<Id, CommunicatorMessage__c>();
        if (threadIds == null || threadIds.isEmpty()) return result;
        for (CommunicatorMessage__c messageRecord : [
            SELECT Id, Thread__c, Body__c, Sender__c, Sender__r.Name
            FROM CommunicatorMessage__c
            WHERE Thread__c IN :threadIds
            ORDER BY Thread__c, SentAt__c DESC, Id DESC
        ]) {
            if (!result.containsKey(messageRecord.Thread__c)) {
                result.put(messageRecord.Thread__c, messageRecord);
            }
        }
        return result;
    }

    private static List<CommunicatorExternalApiDTOs.ConversationItemDTO> applyConversationFilter(
        List<CommunicatorExternalApiDTOs.ConversationItemDTO> items,
        String filter
    ) {
        if (String.isBlank(filter) || filter == 'all') return items;
        List<CommunicatorExternalApiDTOs.ConversationItemDTO> filtered =
            new List<CommunicatorExternalApiDTOs.ConversationItemDTO>();
        for (CommunicatorExternalApiDTOs.ConversationItemDTO item : items) {
            if (filter == 'unread' && item.unreadCount > 0) filtered.add(item);
            if (filter == 'read' && item.unreadCount == 0) filtered.add(item);
        }
        return filtered;
    }

    private static void validateConversationFilter(String filter) {
        if (CONVERSATION_FILTERS.contains(filter)) return;
        if (filter == 'recent') {
            throw CommunicatorExternalApiErrorService.badRequest(
                'UNSUPPORTED_FILTER',
                'filter=recent nao e suportado pela API externa porque RecentlyViewed e vinculado ao usuario autenticado da sessao.'
            );
        }
        throw CommunicatorExternalApiErrorService.badRequest(
            'INVALID_FILTER',
            'filter invalido. Valores aceitos: all, read, unread.'
        );
    }

    private static String normalizeConversationViewMode(String rawViewMode) {
        String viewMode = String.isBlank(rawViewMode) ? 'thread' : rawViewMode.trim().toLowerCase();
        if (viewMode == 'threadstage' || viewMode == 'thread_stage' || viewMode == 'thread-stage') {
            viewMode = 'threadstage';
        }
        if (!CONVERSATION_VIEW_MODES.contains(viewMode)) {
            throw CommunicatorExternalApiErrorService.badRequest(
                'INVALID_VIEW_MODE',
                'viewMode invalido. Valores aceitos: thread, threadStage, opportunity.'
            );
        }
        return viewMode;
    }

    private static List<CommunicatorExternalApiDTOs.ConversationItemDTO> applyConversationViewMode(
        List<CommunicatorExternalApiDTOs.ConversationItemDTO> items,
        String viewMode
    ) {
        if (viewMode == 'opportunity') return buildOpportunityConversationItems(items);
        if (viewMode == 'threadstage') return buildThreadStageConversationItems(items);
        for (CommunicatorExternalApiDTOs.ConversationItemDTO item : items) {
            item.viewMode = 'thread';
        }
        return items;
    }

    private static List<CommunicatorExternalApiDTOs.ConversationItemDTO> buildOpportunityConversationItems(
        List<CommunicatorExternalApiDTOs.ConversationItemDTO> threadItems
    ) {
        Map<String, List<CommunicatorExternalApiDTOs.ConversationItemDTO>> threadsByOpportunity =
            groupThreadsByOpportunity(threadItems);
        List<CommunicatorExternalApiDTOs.ConversationItemDTO> items =
            new List<CommunicatorExternalApiDTOs.ConversationItemDTO>();
        for (String opportunityId : threadsByOpportunity.keySet()) {
            List<CommunicatorExternalApiDTOs.ConversationItemDTO> threads = threadsByOpportunity.get(opportunityId);
            sortConversationItems(threads, 'lastMessageAt', 'desc');
            CommunicatorExternalApiDTOs.ConversationItemDTO selectedItem = threads[0];
            CommunicatorExternalApiDTOs.ConversationItemDTO item = cloneConversationHeader(selectedItem);
            item.viewMode = 'opportunity';
            item.threadId = null;
            item.threadName = null;
            item.currentThreadId = selectedItem.threadId;
            item.threadCount = threads.size();
            item.unreadCount = sumUnread(threads);
            item.isRead = item.unreadCount == 0;
            item.stages = collectStages(threads);
            item.threads = threads;
            items.add(item);
        }
        return items;
    }

    private static List<CommunicatorExternalApiDTOs.ConversationItemDTO> buildThreadStageConversationItems(
        List<CommunicatorExternalApiDTOs.ConversationItemDTO> threadItems
    ) {
        Map<String, List<CommunicatorExternalApiDTOs.ConversationItemDTO>> threadsByStage =
            new Map<String, List<CommunicatorExternalApiDTOs.ConversationItemDTO>>();
        for (CommunicatorExternalApiDTOs.ConversationItemDTO item : threadItems) {
            String key = String.valueOf(item.opportunityId) + '|' + String.valueOf(item.stage);
            if (!threadsByStage.containsKey(key)) {
                threadsByStage.put(key, new List<CommunicatorExternalApiDTOs.ConversationItemDTO>());
            }
            threadsByStage.get(key).add(item);
        }

        List<CommunicatorExternalApiDTOs.ConversationItemDTO> groupedItems =
            new List<CommunicatorExternalApiDTOs.ConversationItemDTO>();
        for (String key : threadsByStage.keySet()) {
            List<CommunicatorExternalApiDTOs.ConversationItemDTO> threads = threadsByStage.get(key);
            sortConversationItems(threads, 'lastMessageAt', 'desc');
            CommunicatorExternalApiDTOs.ConversationItemDTO selectedItem = threads[0];
            CommunicatorExternalApiDTOs.ConversationItemDTO item = cloneConversationHeader(selectedItem);
            item.viewMode = 'threadStage';
            item.threadId = null;
            item.threadName = null;
            item.currentThreadId = selectedItem.threadId;
            item.threadCount = threads.size();
            item.unreadCount = sumUnread(threads);
            item.isRead = item.unreadCount == 0;
            item.threads = threads;
            groupedItems.add(item);
        }
        return groupedItems;
    }

    private static Map<String, List<CommunicatorExternalApiDTOs.ConversationItemDTO>> groupThreadsByOpportunity(
        List<CommunicatorExternalApiDTOs.ConversationItemDTO> threadItems
    ) {
        Map<String, List<CommunicatorExternalApiDTOs.ConversationItemDTO>> threadsByOpportunity =
            new Map<String, List<CommunicatorExternalApiDTOs.ConversationItemDTO>>();
        for (CommunicatorExternalApiDTOs.ConversationItemDTO item : threadItems) {
            String key = String.isBlank(item.opportunityId) ? item.recordId : item.opportunityId;
            if (!threadsByOpportunity.containsKey(key)) {
                threadsByOpportunity.put(key, new List<CommunicatorExternalApiDTOs.ConversationItemDTO>());
            }
            threadsByOpportunity.get(key).add(item);
        }
        return threadsByOpportunity;
    }

    private static CommunicatorExternalApiDTOs.ConversationItemDTO cloneConversationHeader(
        CommunicatorExternalApiDTOs.ConversationItemDTO source
    ) {
        CommunicatorExternalApiDTOs.ConversationItemDTO item =
            new CommunicatorExternalApiDTOs.ConversationItemDTO();
        item.recordId = source.recordId;
        item.recordName = source.recordName;
        item.recordObjectApiName = source.recordObjectApiName;
        item.opportunityId = source.opportunityId;
        item.opportunityName = source.opportunityName;
        item.repasseId = source.repasseId;
        item.repasseName = source.repasseName;
        item.currentStage = source.currentStage;
        item.stage = source.stage;
        item.lastMessageAt = source.lastMessageAt;
        item.lastMessageBody = source.lastMessageBody;
        item.lastSenderId = source.lastSenderId;
        item.lastSenderName = source.lastSenderName;
        item.hasThread = true;
        return item;
    }

    private static Integer sumUnread(List<CommunicatorExternalApiDTOs.ConversationItemDTO> items) {
        Integer total = 0;
        for (CommunicatorExternalApiDTOs.ConversationItemDTO item : items) {
            total += item.unreadCount == null ? 0 : item.unreadCount;
        }
        return total;
    }

    private static List<String> collectStages(List<CommunicatorExternalApiDTOs.ConversationItemDTO> items) {
        Set<String> stageSet = new Set<String>();
        for (CommunicatorExternalApiDTOs.ConversationItemDTO item : items) {
            if (String.isNotBlank(item.stage)) {
                stageSet.add(item.stage);
            }
        }
        List<String> stages = new List<String>();
        for (String stageName : stageSet) {
            stages.add(stageName);
        }
        stages.sort();
        return stages;
    }

    private static void sortConversationItems(
        List<CommunicatorExternalApiDTOs.ConversationItemDTO> items,
        String sortBy,
        String sortDirection
    ) {
        String fieldName =
            CommunicatorExternalApiSortService.validateSortField(sortBy, CONVERSATION_SORT_FIELDS, 'lastMessageAt');
        String direction = CommunicatorExternalApiSortService.normalizeDirection(sortDirection);
        items.sort(new ConversationItemComparator(fieldName, direction));
    }

    private static void sortMessageItems(
        List<CommunicatorExternalApiDTOs.MessageDTO> items,
        String sortBy,
        String sortDirection
    ) {
        String fieldName = CommunicatorExternalApiSortService.validateSortField(sortBy, MESSAGE_SORT_FIELDS, 'sentAt');
        String direction = CommunicatorExternalApiSortService.normalizeDirection(sortDirection);
        items.sort(new MessageItemComparator(fieldName, direction));
    }

    private class ConversationItemComparator implements System.Comparator<CommunicatorExternalApiDTOs.ConversationItemDTO> {
        private String fieldName;
        private String direction;

        ConversationItemComparator(String fieldName, String direction) {
            this.fieldName = fieldName;
            this.direction = direction;
        }

        public Integer compare(
            CommunicatorExternalApiDTOs.ConversationItemDTO firstItem,
            CommunicatorExternalApiDTOs.ConversationItemDTO secondItem
        ) {
            Integer result;
            if (fieldName == 'unreadCount') {
                result = compareIntegers(firstItem.unreadCount, secondItem.unreadCount);
            } else if (fieldName == 'recordName') {
                result = compareStrings(firstItem.recordName, secondItem.recordName);
            } else if (fieldName == 'currentStage') {
                result = compareStrings(firstItem.currentStage, secondItem.currentStage);
            } else {
                result = compareStrings(firstItem.lastMessageAt, secondItem.lastMessageAt);
            }
            if (result == 0) {
                result = compareStrings(firstItem.threadId, secondItem.threadId);
            }
            return direction == 'desc' ? -result : result;
        }
    }

    private class MessageItemComparator implements System.Comparator<CommunicatorExternalApiDTOs.MessageDTO> {
        private String fieldName;
        private String direction;

        MessageItemComparator(String fieldName, String direction) {
            this.fieldName = fieldName;
            this.direction = direction;
        }

        public Integer compare(
            CommunicatorExternalApiDTOs.MessageDTO firstItem,
            CommunicatorExternalApiDTOs.MessageDTO secondItem
        ) {
            Integer result = compareStrings(firstItem.sentAt, secondItem.sentAt);
            if (result == 0) {
                result = compareStrings(firstItem.messageId, secondItem.messageId);
            }
            return direction == 'desc' ? -result : result;
        }
    }

    private static void sortGroupItems(
        List<CommunicatorExternalApiDTOs.GroupItemDTO> items,
        String sortBy,
        String sortDirection
    ) {
        String fieldName = CommunicatorExternalApiSortService.validateSortField(
            sortBy,
            GROUP_SORT_FIELDS,
            'name'
        );
        String direction = CommunicatorExternalApiSortService.normalizeDirection(sortDirection);
        items.sort(new GroupItemComparator(fieldName, direction));
    }

    private class GroupItemComparator implements System.Comparator<CommunicatorExternalApiDTOs.GroupItemDTO> {
        private String fieldName;
        private String direction;

        GroupItemComparator(String fieldName, String direction) {
            this.fieldName = fieldName;
            this.direction = direction;
        }

        public Integer compare(
            CommunicatorExternalApiDTOs.GroupItemDTO firstItem,
            CommunicatorExternalApiDTOs.GroupItemDTO secondItem
        ) {
            Integer result = fieldName == 'memberCount'
                ? compareIntegers(firstItem.memberCount, secondItem.memberCount)
                : fieldName == 'unreadCount'
                    ? compareIntegers(firstItem.unreadCount, secondItem.unreadCount)
                    : compareStrings(getStringValue(firstItem), getStringValue(secondItem));
            return direction == 'desc' ? -result : result;
        }

        private String getStringValue(CommunicatorExternalApiDTOs.GroupItemDTO item) {
            if (fieldName == 'memberCount') return String.valueOf(item.memberCount);
            if (fieldName == 'unreadCount') return String.valueOf(item.unreadCount);
            if (fieldName == 'lastActivityAt') return item.lastActivityAt;
            return item.groupName;
        }
    }

    private static Integer compareStrings(String leftValue, String rightValue) {
        String leftText = leftValue == null ? '' : leftValue.toLowerCase();
        String rightText = rightValue == null ? '' : rightValue.toLowerCase();
        if (leftText == rightText) return 0;
        return leftText < rightText ? -1 : 1;
    }

    private static Integer compareIntegers(Integer leftValue, Integer rightValue) {
        Integer leftNumber = leftValue == null ? 0 : leftValue;
        Integer rightNumber = rightValue == null ? 0 : rightValue;
        if (leftNumber == rightNumber) return 0;
        return leftNumber < rightNumber ? -1 : 1;
    }

    private static List<CommunicatorExternalApiDTOs.ConversationItemDTO> paginateConversationItems(
        List<CommunicatorExternalApiDTOs.ConversationItemDTO> items,
        Integer pageSize,
        Integer offsetValue
    ) {
        if (items.isEmpty() || offsetValue >= items.size()) {
            return new List<CommunicatorExternalApiDTOs.ConversationItemDTO>();
        }
        Integer endIndex = Math.min(offsetValue + pageSize, items.size());
        List<CommunicatorExternalApiDTOs.ConversationItemDTO> pageItems =
            new List<CommunicatorExternalApiDTOs.ConversationItemDTO>();
        for (Integer index = offsetValue; index < endIndex; index++) {
            pageItems.add(items[index]);
        }
        return pageItems;
    }

    private static CommunicatorExternalApiDTOs.ApiResponseDTO buildListResponse(
        List<CommunicatorExternalApiDTOs.GroupItemDTO> items,
        CommunicatorExternalApiDTOs.UserContextDTO context,
        Map<String, String> params,
        String examplePath
    ) {
        Integer totalItems = items == null ? 0 : items.size();
        if (!hasPagination(params)) {
            CommunicatorExternalApiPaginationService.validateNonPaginatedLimit(totalItems, examplePath);
            return successResponse(items, context.timezoneSidKey);
        }

        Integer pageSize = toInteger(params.get('pageSize'));
        Integer pageNumber = toInteger(params.get('pageNumber'));
        Integer normalizedPageSize = CommunicatorExternalApiPaginationService.normalizePageSize(pageSize);
        Integer normalizedPageNumber = CommunicatorExternalApiPaginationService.normalizePageNumber(pageNumber);
        Integer offsetValue = CommunicatorExternalApiPaginationService.calculateOffset(pageSize, pageNumber);
        CommunicatorExternalApiDTOs.ApiResponseDTO response =
            successResponse(paginateGroupItems(items, normalizedPageSize, offsetValue), context.timezoneSidKey);
        response.page = CommunicatorExternalApiPaginationService.buildPage(
            normalizedPageSize,
            normalizedPageNumber,
            totalItems,
            null
        );
        return response;
    }

    private static List<CommunicatorExternalApiDTOs.GroupItemDTO> paginateGroupItems(
        List<CommunicatorExternalApiDTOs.GroupItemDTO> items,
        Integer pageSize,
        Integer offsetValue
    ) {
        if (items == null || items.isEmpty() || offsetValue >= items.size()) {
            return new List<CommunicatorExternalApiDTOs.GroupItemDTO>();
        }
        Integer endIndex = Math.min(offsetValue + pageSize, items.size());
        List<CommunicatorExternalApiDTOs.GroupItemDTO> pageItems =
            new List<CommunicatorExternalApiDTOs.GroupItemDTO>();
        for (Integer index = offsetValue; index < endIndex; index++) {
            pageItems.add(items[index]);
        }
        return pageItems;
    }

    private static CommunicatorExternalApiDTOs.ChatThreadDTO buildThreadChat(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        Id threadId,
        Integer pageSize,
        Integer pageNumber
    ) {
        Integer normalizedPageSize = CommunicatorExternalApiPaginationService.normalizePageSize(pageSize);
        Integer offsetValue = CommunicatorExternalApiPaginationService.calculateOffset(pageSize, pageNumber);
        CommunicatorThread__c threadRecord = [
            SELECT Id, Name, RecordId__c, RecordType__c, Stage__c
            FROM CommunicatorThread__c
            WHERE Id = :threadId
            LIMIT 1
        ];
        Id opportunityId = null;
        if (threadRecord.RecordType__c == 'Opportunity') {
            opportunityId = tryParseId(threadRecord.RecordId__c);
        } else if (threadRecord.RecordType__c == 'Repasse__c') {
            opportunityId = tryParseId(
                CommunicatorThreadService.resolveOpportunityIdIfRepasse(threadRecord.RecordId__c)
            );
        }
        Opportunity opportunityRecord;
        if (opportunityId != null) {
            List<Opportunity> opportunityRows = [
                SELECT Id, Name, StageName
                FROM Opportunity
                WHERE Id = :opportunityId
                LIMIT 1
            ];
            opportunityRecord = opportunityRows.isEmpty() ? null : opportunityRows[0];
        }
        Repasse__c repasseRecord = opportunityId == null
            ? null
            : CommunicatorRepasseService.getLatestRepassesByOpportunityIds(new Set<Id>{ opportunityId }).get(opportunityId);
        List<CommunicatorMessage__c> messages = [
            SELECT Id, Name, Body__c, Subject__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                   SentAt__c, EditedAt__c, HasMention__c, IsSystemMessage__c, MentionedUserIds__c,
                   MentionedGroupIds__c, Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                   Thread__c, Thread__r.Name, Thread__r.Stage__c
            FROM CommunicatorMessage__c
            WHERE Thread__c = :threadId
            ORDER BY SentAt__c ASC, Id ASC
            LIMIT :normalizedPageSize
            OFFSET :offsetValue
        ];

        CommunicatorExternalApiDTOs.ChatThreadDTO chat =
            new CommunicatorExternalApiDTOs.ChatThreadDTO();
        chat.threadId = String.valueOf(threadRecord.Id);
        chat.threadName = threadRecord.Name;
        chat.recordId = threadRecord.RecordId__c;
        chat.recordObjectApiName = threadRecord.RecordType__c;
        chat.stage = threadRecord.Stage__c;
        chat.opportunityId = opportunityId == null ? null : String.valueOf(opportunityId);
        chat.opportunityName = opportunityRecord == null ? null : opportunityRecord.Name;
        chat.recordName = opportunityRecord != null
            ? opportunityRecord.Name
            : CommunicatorExternalApiNameResolver.getRecordName(tryParseId(threadRecord.RecordId__c));
        chat.currentStage = resolveCurrentStageForOpportunity(opportunityRecord, repasseRecord);
        chat.repasseId = repasseRecord == null ? null : String.valueOf(repasseRecord.Id);
        chat.repasseName = repasseRecord == null ? null : repasseRecord.Name;
        chat.unreadCount = loadUnreadByThread(context.userId, new Set<Id>{ threadId }).get(threadId);
        chat.messages = mapMessages(context, messages);
        chat.participants = loadParticipants(threadId, context.timezoneSidKey);
        return chat;
    }

    private static CommunicatorExternalApiDTOs.ChatThreadDTO buildEmptyGroupChat(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        Id groupId
    ) {
        CommunicatorExternalApiDTOs.ChatThreadDTO chat =
            new CommunicatorExternalApiDTOs.ChatThreadDTO();
        chat.recordId = String.valueOf(groupId);
        chat.recordObjectApiName = 'CommunicatorGroup__c';
        chat.recordName = CommunicatorExternalApiNameResolver.getRecordName(groupId);
        chat.unreadCount = 0;
        chat.messages = new List<CommunicatorExternalApiDTOs.MessageDTO>();
        chat.participants = context.broadcastGroupIds.contains(groupId)
            ? new List<CommunicatorExternalApiDTOs.ParticipantDTO>()
            : loadGroupMembers(groupId);
        return chat;
    }

    private static List<CommunicatorMessage__c> queryThreadMessages(
        Id threadId,
        Integer pageSize,
        Integer offsetValue,
        String direction
    ) {
        Integer safeSize = CommunicatorExternalApiPaginationService.normalizePageSize(pageSize);
        Integer safeOffset = offsetValue != null && offsetValue > 0 ? offsetValue : 0;
        if (direction == 'desc') {
            return [
                SELECT Id, Name, Body__c, Subject__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                       SentAt__c, EditedAt__c, HasMention__c, IsSystemMessage__c, MentionedUserIds__c,
                       MentionedGroupIds__c, Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                       Thread__c, Thread__r.Name, Thread__r.Stage__c
                FROM CommunicatorMessage__c
                WHERE Thread__c = :threadId
                ORDER BY SentAt__c DESC, Id DESC
                LIMIT :safeSize
                OFFSET :safeOffset
            ];
        }
        return [
            SELECT Id, Name, Body__c, Subject__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                   SentAt__c, EditedAt__c, HasMention__c, IsSystemMessage__c, MentionedUserIds__c,
                   MentionedGroupIds__c, Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                   Thread__c, Thread__r.Name, Thread__r.Stage__c
            FROM CommunicatorMessage__c
            WHERE Thread__c = :threadId
            ORDER BY SentAt__c ASC, Id ASC
            LIMIT :safeSize
            OFFSET :safeOffset
        ];
    }

    private static List<CommunicatorMessage__c> queryRecordMessages(
        Set<Id> threadIds,
        Integer pageSize,
        Integer offsetValue,
        String direction
    ) {
        Integer safeSize = CommunicatorExternalApiPaginationService.normalizePageSize(pageSize);
        Integer safeOffset = offsetValue != null && offsetValue > 0 ? offsetValue : 0;
        if (direction == 'asc') {
            return [
                SELECT Id, Name, Body__c, Subject__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                       SentAt__c, EditedAt__c, HasMention__c, IsSystemMessage__c, MentionedUserIds__c,
                       MentionedGroupIds__c, Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                       Thread__c, Thread__r.Name, Thread__r.Stage__c
                FROM CommunicatorMessage__c
                WHERE Thread__c IN :threadIds
                ORDER BY SentAt__c ASC, Id ASC
                LIMIT :safeSize
                OFFSET :safeOffset
            ];
        }
        return [
            SELECT Id, Name, Body__c, Subject__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                   SentAt__c, EditedAt__c, HasMention__c, IsSystemMessage__c, MentionedUserIds__c,
                   MentionedGroupIds__c, Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                   Thread__c, Thread__r.Name, Thread__r.Stage__c
            FROM CommunicatorMessage__c
            WHERE Thread__c IN :threadIds
            ORDER BY SentAt__c DESC, Id DESC
            LIMIT :safeSize
            OFFSET :safeOffset
        ];
    }

    private static List<CommunicatorExternalApiDTOs.ParticipantDTO> loadParticipants(
        Id threadId,
        String timezoneSidKey
    ) {
        List<CommunicatorExternalApiDTOs.ParticipantDTO> items =
            new List<CommunicatorExternalApiDTOs.ParticipantDTO>();
        for (CommunicatorParticipant__c participant : [
            SELECT Id, User__c, User__r.Name, User__r.SmallPhotoUrl, Role__c, LastReadAt__c
            FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId
            AND IsActive__c = true
            ORDER BY User__r.Name ASC
        ]) {
            CommunicatorExternalApiDTOs.ParticipantDTO item =
                new CommunicatorExternalApiDTOs.ParticipantDTO();
            item.participantId = String.valueOf(participant.Id);
            item.userId = String.valueOf(participant.User__c);
            item.userName = participant.User__r == null ? null : participant.User__r.Name;
            item.photoUrl = participant.User__r == null ? null : participant.User__r.SmallPhotoUrl;
            item.role = participant.Role__c;
            item.lastReadAt = CommunicatorExternalApiDateTimeService.formatForUser(
                participant.LastReadAt__c,
                timezoneSidKey
            );
            items.add(item);
        }
        return items;
    }

    private static List<CommunicatorExternalApiDTOs.MessageDTO> mapMessages(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        List<CommunicatorMessage__c> messages
    ) {
        List<CommunicatorExternalApiDTOs.MessageDTO> items =
            new List<CommunicatorExternalApiDTOs.MessageDTO>();
        if (messages == null || messages.isEmpty()) return items;

        Set<Id> messageIds = new Set<Id>();
        Set<Id> mentionedUserIds = new Set<Id>();
        Set<Id> mentionedGroupIds = new Set<Id>();
        for (CommunicatorMessage__c messageRecord : messages) {
            messageIds.add(messageRecord.Id);
            mentionedUserIds.addAll(CommunicatorMentionService.deserializeUserIds(messageRecord.MentionedUserIds__c));
            mentionedGroupIds.addAll(CommunicatorMentionService.deserializeUserIds(messageRecord.MentionedGroupIds__c));
        }
        Map<Id, String> userNamesById = CommunicatorExternalApiNameResolver.getUserNames(mentionedUserIds);
        Map<Id, String> groupNamesById = CommunicatorExternalApiNameResolver.getGroupNames(mentionedGroupIds);
        Map<String, List<CommunicatorExternalApiDTOs.AttachmentDTO>> attachmentsByMessageId =
            loadAttachmentsByMessageId(messageIds);
        Boolean canReadBody = canReadMessageField(context, 'Body__c');
        Boolean canReadSubject = canReadMessageField(context, 'Subject__c');
        Boolean canReadStatus = canReadMessageField(context, 'Status__c');
        Boolean canReadSentAt = canReadMessageField(context, 'SentAt__c');
        Boolean canReadEditedAt = canReadMessageField(context, 'EditedAt__c');
        Boolean canReadSender = canReadMessageField(context, 'Sender__c');
        Boolean canReadSystem = canReadMessageField(context, 'IsSystemMessage__c');
        Boolean canReadMention = canReadMessageField(context, 'HasMention__c');
        Boolean canReadAttachment = canReadMessageField(context, 'HasAttachment__c');

        for (CommunicatorMessage__c messageRecord : messages) {
            CommunicatorExternalApiDTOs.MessageDTO item =
                new CommunicatorExternalApiDTOs.MessageDTO();
            item.messageId = String.valueOf(messageRecord.Id);
            item.threadId = messageRecord.Thread__c == null ? null : String.valueOf(messageRecord.Thread__c);
            item.threadName = messageRecord.Thread__r == null ? null : messageRecord.Thread__r.Name;
            item.stage = messageRecord.Thread__r == null ? null : messageRecord.Thread__r.Stage__c;
            item.body = canReadBody ? messageRecord.Body__c : null;
            item.subject = canReadSubject ? (String) messageRecord.get('Subject__c') : null;
            item.status = canReadStatus ? messageRecord.Status__c : null;
            item.sentAt = canReadSentAt
                ? CommunicatorExternalApiDateTimeService.formatForUser(
                    messageRecord.SentAt__c,
                    context.timezoneSidKey
                )
                : null;
            Datetime editedAt = (Datetime) messageRecord.get('EditedAt__c');
            item.editedAt = canReadEditedAt
                ? CommunicatorExternalApiDateTimeService.formatForUser(
                    editedAt,
                    context.timezoneSidKey
                )
                : null;
            item.senderId = canReadSender && messageRecord.Sender__c != null
                ? String.valueOf(messageRecord.Sender__c)
                : null;
            item.senderName = item.senderId == null || messageRecord.Sender__r == null
                ? null
                : messageRecord.Sender__r.Name;
            item.senderPhotoUrl = item.senderId == null || messageRecord.Sender__r == null
                ? null
                : messageRecord.Sender__r.SmallPhotoUrl;
            item.isSystemMessage = canReadSystem ? messageRecord.IsSystemMessage__c : null;
            item.hasMention = canReadMention ? messageRecord.HasMention__c : null;
            item.hasAttachment = canReadAttachment ? messageRecord.HasAttachment__c : null;
            item.mentionedUsers = mapIdNamePairs(
                CommunicatorMentionService.deserializeUserIds(messageRecord.MentionedUserIds__c),
                userNamesById
            );
            item.mentionedGroups = mapIdNamePairs(
                CommunicatorMentionService.deserializeUserIds(messageRecord.MentionedGroupIds__c),
                groupNamesById
            );
            item.attachments = attachmentsByMessageId.containsKey(item.messageId)
                ? attachmentsByMessageId.get(item.messageId)
                : new List<CommunicatorExternalApiDTOs.AttachmentDTO>();
            items.add(item);
        }
        return items;
    }

    private static Boolean canReadMessageField(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        String fieldApiName
    ) {
        return CommunicatorExternalApiAccessService.canReadField(
            context,
            'CommunicatorMessage__c',
            fieldApiName
        );
    }

    private static Map<String, List<CommunicatorExternalApiDTOs.AttachmentDTO>> loadAttachmentsByMessageId(
        Set<Id> messageIds
    ) {
        Map<String, List<CommunicatorExternalApiDTOs.AttachmentDTO>> attachmentsByMessageId =
            new Map<String, List<CommunicatorExternalApiDTOs.AttachmentDTO>>();
        if (messageIds == null || messageIds.isEmpty()) return attachmentsByMessageId;

        List<CommunicatorDTOs.MessageAttachmentDTO> attachments =
            CommunicatorMessageService.getMessageAttachments(new List<Id>(messageIds));
        Map<String, String> versionIdsByDocumentId =
            CommunicatorFileShareService.getLatestVersionIds(collectDocumentIds(attachments));

        for (CommunicatorDTOs.MessageAttachmentDTO attachment : attachments) {
            if (!attachmentsByMessageId.containsKey(attachment.messageId)) {
                attachmentsByMessageId.put(
                    attachment.messageId,
                    new List<CommunicatorExternalApiDTOs.AttachmentDTO>()
                );
            }
            CommunicatorExternalApiDTOs.AttachmentDTO item =
                new CommunicatorExternalApiDTOs.AttachmentDTO();
            item.contentDocumentId = attachment.contentDocumentId;
            item.contentVersionId = versionIdsByDocumentId.get(attachment.contentDocumentId);
            item.fileName = attachment.fileName;
            attachmentsByMessageId.get(attachment.messageId).add(item);
        }
        return attachmentsByMessageId;
    }

    private static List<String> collectDocumentIds(List<CommunicatorDTOs.MessageAttachmentDTO> attachments) {
        List<String> documentIds = new List<String>();
        if (attachments == null) return documentIds;
        for (CommunicatorDTOs.MessageAttachmentDTO attachment : attachments) {
            if (String.isNotBlank(attachment.contentDocumentId)) {
                documentIds.add(attachment.contentDocumentId);
            }
        }
        return documentIds;
    }

    private static List<CommunicatorExternalApiDTOs.IdNamePairDTO> mapIdNamePairs(
        Set<Id> ids,
        Map<Id, String> namesById
    ) {
        List<CommunicatorExternalApiDTOs.IdNamePairDTO> items =
            new List<CommunicatorExternalApiDTOs.IdNamePairDTO>();
        if (ids == null || ids.isEmpty()) return items;
        for (Id typedId : ids) {
            CommunicatorExternalApiDTOs.IdNamePairDTO item =
                new CommunicatorExternalApiDTOs.IdNamePairDTO();
            item.id = String.valueOf(typedId);
            item.name = namesById.get(typedId);
            items.add(item);
        }
        return items;
    }

    private static CommunicatorMessage__c createRepresentedMessage(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        Id threadId,
        String body,
        List<String> mentionedUserIds,
        List<String> mentionedGroupIds,
        String contentDocumentId,
        String contentVersionId
    ) {
        if (String.isBlank(body) && String.isBlank(contentDocumentId) && String.isBlank(contentVersionId)) {
            throw CommunicatorExternalApiErrorService.badRequest(
                'MESSAGE_CONTENT_REQUIRED',
                'body ou anexo e obrigatorio.'
            );
        }

        Set<Id> userMentionIds = toIdSet(mentionedUserIds, 'User');
        Set<Id> groupMentionIds = toIdSet(mentionedGroupIds, 'CommunicatorGroup__c');
        Set<Id> allMentionIds = new Set<Id>();
        allMentionIds.addAll(userMentionIds);
        allMentionIds.addAll(groupMentionIds);

        String recordStatus = resolveThreadRecordStatus(threadId);
        Set<Id> resolvedMentionUserIds = resolveMentionUsersForRepresentedUser(context.userId, allMentionIds);
        validateRepresentedMessagingIsOpen(threadId);
        Set<Id> participantUserIds = new Set<Id>{ context.userId };
        participantUserIds.addAll(resolvedMentionUserIds);
        CommunicatorParticipantService.ensureParticipants(threadId, participantUserIds, 'Member');

        List<Id> attachmentIds = new List<Id>();
        if (String.isNotBlank(contentDocumentId)) {
            attachmentIds.add(parseContentDocumentId(contentDocumentId));
        } else if (String.isNotBlank(contentVersionId)) {
            attachmentIds.add(resolveContentDocumentIdFromVersion(contentVersionId));
        }

        CommunicatorMessage__c messageRecord = new CommunicatorMessage__c(
            Thread__c = threadId,
            Body__c = String.isBlank(body) ? null : body.trim(),
            Sender__c = context.userId,
            SentAt__c = System.now(),
            Status__c = 'Sent',
            HasAttachment__c = !attachmentIds.isEmpty(),
            ContentDocumentId__c = attachmentIds.isEmpty() ? null : String.valueOf(attachmentIds[0]),
            RecordStatus__c = recordStatus,
            HasMention__c = !resolvedMentionUserIds.isEmpty() || !groupMentionIds.isEmpty(),
            MentionedUserIds__c = CommunicatorMentionService.serializeUserIds(resolvedMentionUserIds),
            MentionedGroupIds__c = CommunicatorMentionService.serializeUserIds(groupMentionIds)
        );
        insert messageRecord;

        if (!attachmentIds.isEmpty()) {
            Id opportunityId = resolveThreadOpportunityId(threadId);
            CommunicatorFileShareService.ensureAccessForAttachments(attachmentIds, threadId, opportunityId);
            List<ContentDocumentLink> links = new List<ContentDocumentLink>();
            for (Id attachmentId : attachmentIds) {
                links.add(new ContentDocumentLink(
                    ContentDocumentId = attachmentId,
                    LinkedEntityId = messageRecord.Id,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                ));
            }
            Database.insert(links, false);
        }

        update new CommunicatorThread__c(Id = threadId, LastMessageAt__c = System.now());
        mirrorRepresentedMessageToGroupThreads(messageRecord, groupMentionIds);
        createNotificationsForRepresentedMessage(context.userId, threadId, messageRecord.Id, resolvedMentionUserIds);

        return [
            SELECT Id, Name, Body__c, Subject__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                   SentAt__c, EditedAt__c, HasMention__c, IsSystemMessage__c, MentionedUserIds__c,
                   MentionedGroupIds__c, Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                   Thread__c, Thread__r.Name, Thread__r.Stage__c
            FROM CommunicatorMessage__c
            WHERE Id = :messageRecord.Id
            LIMIT 1
        ];
    }

    private static void createNotificationsForRepresentedMessage(
        Id senderUserId,
        Id threadId,
        Id messageId,
        Set<Id> mentionedUserIds
    ) {
        Set<Id> recipientIds = new Set<Id>();
        for (CommunicatorParticipant__c participant : [
            SELECT User__c
            FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId
            AND IsActive__c = true
        ]) {
            if (participant.User__c != null && participant.User__c != senderUserId) {
                recipientIds.add(participant.User__c);
            }
        }
        Set<Id> mentionRecipients = new Set<Id>(mentionedUserIds);
        mentionRecipients.retainAll(recipientIds);
        if (!mentionRecipients.isEmpty()) {
            CommunicatorNotificationRecordService.createNotificationsIfMissing(
                messageId,
                threadId,
                mentionRecipients,
                true
            );
        }
        recipientIds.removeAll(mentionRecipients);
        if (!recipientIds.isEmpty()) {
            CommunicatorNotificationRecordService.createNotificationsIfMissing(
                messageId,
                threadId,
                recipientIds,
                false
            );
        }
    }

    private static void mirrorRepresentedMessageToGroupThreads(
        CommunicatorMessage__c sourceMessage,
        Set<Id> groupIds
    ) {
        if (sourceMessage == null || groupIds == null || groupIds.isEmpty()) return;
        List<CommunicatorMessage__c> mirrors = new List<CommunicatorMessage__c>();
        List<Id> groupThreadIds = new List<Id>();
        for (Id groupId : groupIds) {
            CommunicatorThread__c groupThread = CommunicatorThreadService.getOrCreateGroupThread(groupId);
            mirrors.add(new CommunicatorMessage__c(
                Thread__c = groupThread.Id,
                Body__c = sourceMessage.Body__c,
                Sender__c = sourceMessage.Sender__c,
                SentAt__c = sourceMessage.SentAt__c,
                Status__c = 'Sent',
                IsSystemMessage__c = false,
                HasMention__c = false,
                HasAttachment__c = sourceMessage.HasAttachment__c,
                ContentDocumentId__c = sourceMessage.ContentDocumentId__c,
                RecordStatus__c = sourceMessage.RecordStatus__c,
                SourceThreadId__c = String.valueOf(sourceMessage.Thread__c)
            ));
            groupThreadIds.add(groupThread.Id);
        }
        if (mirrors.isEmpty()) return;
        insert mirrors;
        List<Id> attachmentIds = sourceMessage.HasAttachment__c == true
            ? loadMessageAttachmentIds(sourceMessage.Id, sourceMessage.ContentDocumentId__c)
            : new List<Id>();
        linkAttachmentsToMirrors(mirrors, groupThreadIds, attachmentIds);
        for (Id groupThreadId : groupThreadIds) {
            update new CommunicatorThread__c(Id = groupThreadId, LastMessageAt__c = sourceMessage.SentAt__c);
        }
    }

    private static List<Id> loadMessageAttachmentIds(Id messageId, String contentDocumentId) {
        Set<Id> attachmentIds = new Set<Id>();
        Id directAttachmentId = tryParseId(contentDocumentId);
        if (directAttachmentId != null) attachmentIds.add(directAttachmentId);
        for (ContentDocumentLink linkRecord : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :messageId
        ]) {
            attachmentIds.add(linkRecord.ContentDocumentId);
        }
        return new List<Id>(attachmentIds);
    }

    private static void linkAttachmentsToMirrors(
        List<CommunicatorMessage__c> mirrors,
        List<Id> groupThreadIds,
        List<Id> attachmentIds
    ) {
        if (attachmentIds == null || attachmentIds.isEmpty()) return;
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (Integer index = 0; index < mirrors.size(); index++) {
            Id groupThreadId = groupThreadIds[index];
            for (Id attachmentId : attachmentIds) {
                CommunicatorFileShareService.ensureAccessForAttachment(attachmentId, groupThreadId);
                links.add(new ContentDocumentLink(
                    ContentDocumentId = attachmentId,
                    LinkedEntityId = mirrors[index].Id,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                ));
            }
        }
        if (!links.isEmpty()) Database.insert(links, false);
    }

    private static Set<Id> resolveMentionUsersForRepresentedUser(Id senderUserId, Set<Id> mentionIds) {
        if (mentionIds == null || mentionIds.isEmpty()) return new Set<Id>();
        Set<Id> userIds = new Set<Id>();
        Set<Id> groupIds = new Set<Id>();
        for (Id mentionId : mentionIds) {
            if (mentionId.getSObjectType() == User.SObjectType) {
                userIds.add(mentionId);
            } else if (mentionId.getSObjectType() == CommunicatorGroup__c.SObjectType) {
                groupIds.add(mentionId);
            }
        }
        if (!groupIds.isEmpty()) {
            userIds.addAll(CommunicatorGroupService.getMemberUserIds(groupIds));
        }
        userIds.remove(senderUserId);
        return userIds;
    }

    private static String resolveThreadRecordStatus(Id threadId) {
        List<CommunicatorThread__c> threadRows = [
            SELECT RecordId__c, RecordType__c, Stage__c
            FROM CommunicatorThread__c
            WHERE Id = :threadId
            LIMIT 1
        ];
        if (threadRows.isEmpty()) return null;
        CommunicatorThread__c threadRecord = threadRows[0];
        if (String.isNotBlank(threadRecord.Stage__c)) return threadRecord.Stage__c;
        return CommunicatorRecordStatusService.getRecordStatus(
            threadRecord.RecordId__c,
            threadRecord.RecordType__c
        );
    }

    private static void validateRepresentedMessagingIsOpen(Id threadId) {
        List<CommunicatorThread__c> threadRows = [
            SELECT RecordId__c, RecordType__c, Stage__c
            FROM CommunicatorThread__c
            WHERE Id = :threadId
            LIMIT 1
        ];
        if (threadRows.isEmpty()) return;
        CommunicatorThread__c threadRecord = threadRows[0];
        if (threadRecord.RecordType__c != 'Opportunity' || String.isBlank(threadRecord.RecordId__c)) return;
        String stage = String.isBlank(threadRecord.Stage__c) ? null : threadRecord.Stage__c.trim().toLowerCase();
        if (stage == 'repasse' || stage == 'registro de repasse') return;
        Id opportunityId = tryParseId(threadRecord.RecordId__c);
        if (opportunityId == null) return;

        List<Opportunity> opportunities = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
        if (!opportunities.isEmpty() && opportunities[0].StageName == 'Fechado e ganho') {
            throw CommunicatorExternalApiErrorService.unprocessable(
                'MESSAGING_CLOSED_RECORD',
                'Envio de mensagens bloqueado: oportunidade encerrada e em etapa de repasse.'
            );
        }
    }

    private static Id resolveThreadOpportunityId(Id threadId) {
        List<CommunicatorThread__c> threadRows = [
            SELECT RecordId__c, RecordType__c
            FROM CommunicatorThread__c
            WHERE Id = :threadId
            LIMIT 1
        ];
        if (threadRows.isEmpty()) return null;
        CommunicatorThread__c threadRecord = threadRows[0];
        if (threadRecord.RecordType__c == 'Opportunity') {
            return tryParseId(threadRecord.RecordId__c);
        }
        return tryParseId(CommunicatorThreadService.resolveOpportunityIdIfRepasse(threadRecord.RecordId__c));
    }

    private static void markThreadAsReadForUser(Id userId, Id threadId, String readAtRaw) {
        Datetime readAt = String.isBlank(readAtRaw) ? System.now() :
            CommunicatorExternalApiDateTimeService.parseIsoDatetime(readAtRaw);
        List<CommunicatorParticipant__c> participants = [
            SELECT Id
            FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId
            AND User__c = :userId
            LIMIT 1
        ];
        if (participants.isEmpty()) {
            insert new CommunicatorParticipant__c(
                Thread__c = threadId,
                User__c = userId,
                IsActive__c = true,
                LastReadAt__c = readAt
            );
        } else {
            update new CommunicatorParticipant__c(
                Id = participants[0].Id,
                LastReadAt__c = readAt
            );
        }

        List<CommunicatorNotification__c> unread = [
            SELECT Id
            FROM CommunicatorNotification__c
            WHERE Thread__c = :threadId
            AND Recipient__c = :userId
            AND IsRead__c = false
        ];
        for (CommunicatorNotification__c notification : unread) {
            notification.IsRead__c = true;
            notification.ReadAt__c = readAt;
        }
        if (!unread.isEmpty()) {
            update unread;
        }
    }

    private static List<CommunicatorExternalApiDTOs.NotificationItemDTO> mapNotifications(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        List<CommunicatorNotification__c> notifications
    ) {
        List<CommunicatorExternalApiDTOs.NotificationItemDTO> items =
            new List<CommunicatorExternalApiDTOs.NotificationItemDTO>();
        for (CommunicatorNotification__c notification : notifications) {
            CommunicatorExternalApiDTOs.NotificationItemDTO item =
                new CommunicatorExternalApiDTOs.NotificationItemDTO();
            item.notificationId = String.valueOf(notification.Id);
            item.notificationName = notification.Name;
            item.messageId = notification.Message__c == null ? null : String.valueOf(notification.Message__c);
            item.messageName = notification.Message__r == null ? null : notification.Message__r.Name;
            item.threadId = notification.Thread__c == null ? null : String.valueOf(notification.Thread__c);
            item.threadName = notification.Thread__r == null ? null : notification.Thread__r.Name;
            item.recipientId = notification.Recipient__c == null ? null : String.valueOf(notification.Recipient__c);
            item.recipientName = notification.Recipient__r == null ? null : notification.Recipient__r.Name;
            item.recordId = notification.Thread__r == null ? null : notification.Thread__r.RecordId__c;
            item.recordName = item.recordId == null ? null : CommunicatorExternalApiNameResolver.getRecordName((Id) item.recordId);
            item.type = notification.Type__c;
            item.isRead = notification.IsRead__c;
            item.readState = notification.IsRead__c ? 'read' : 'unread';
            item.isRecent = notification.CreatedDate != null &&
                notification.CreatedDate.addDays(7) >= System.now();
            item.sentAt = CommunicatorExternalApiDateTimeService.formatForUser(
                notification.CreatedDate,
                context.timezoneSidKey
            );
            item.readAt = CommunicatorExternalApiDateTimeService.formatForUser(
                notification.ReadAt__c,
                context.timezoneSidKey
            );
            items.add(item);
        }
        return items;
    }

    private static List<CommunicatorExternalApiDTOs.GroupItemDTO> loadConventionalGroups(
        CommunicatorExternalApiDTOs.UserContextDTO context
    ) {
        List<CommunicatorExternalApiDTOs.GroupItemDTO> items =
            new List<CommunicatorExternalApiDTOs.GroupItemDTO>();
        for (Id groupId : context.conventionalGroupIds) {
            items.add(loadConventionalGroupItem(context, groupId));
        }
        return items;
    }

    private static CommunicatorExternalApiDTOs.GroupItemDTO loadConventionalGroupItem(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        Id groupId
    ) {
        CommunicatorGroup__c groupRecord = [
            SELECT Id, Name, Description__c, Type__c, MemberCount__c, CreatedByUser__c, CreatedByUser__r.Name
            FROM CommunicatorGroup__c
            WHERE Id = :groupId
            LIMIT 1
        ];
        CommunicatorExternalApiDTOs.GroupItemDTO item =
            new CommunicatorExternalApiDTOs.GroupItemDTO();
        item.groupId = String.valueOf(groupRecord.Id);
        item.groupName = groupRecord.Name;
        item.description = groupRecord.Description__c;
        item.type = groupRecord.Type__c;
        item.memberCount = groupRecord.MemberCount__c == null ? 0 : Integer.valueOf(groupRecord.MemberCount__c);
        item.createdByUserId = groupRecord.CreatedByUser__c == null ? null : String.valueOf(groupRecord.CreatedByUser__c);
        item.createdByUserName = groupRecord.CreatedByUser__r == null ? null : groupRecord.CreatedByUser__r.Name;
        Id threadId = findActiveGroupThreadId(groupRecord.Id, false);
        item.threadId = threadId == null ? null : String.valueOf(threadId);
        item.unreadCount = 0;
        if (threadId != null) {
            Map<Id, Integer> unreadByThread = loadUnreadByThread(context.userId, new Set<Id>{ threadId });
            item.unreadCount = unreadByThread.containsKey(threadId) ? unreadByThread.get(threadId) : 0;
            CommunicatorThread__c threadRecord = [
                SELECT LastMessageAt__c
                FROM CommunicatorThread__c
                WHERE Id = :threadId
                LIMIT 1
            ];
            item.lastActivityAt = CommunicatorExternalApiDateTimeService.formatForUser(
                threadRecord.LastMessageAt__c,
                context.timezoneSidKey
            );
        }
        return item;
    }

    private static List<CommunicatorExternalApiDTOs.GroupItemDTO> loadBroadcastGroups(
        CommunicatorExternalApiDTOs.UserContextDTO context
    ) {
        List<CommunicatorExternalApiDTOs.GroupItemDTO> items =
            new List<CommunicatorExternalApiDTOs.GroupItemDTO>();
        if (context.broadcastGroupIds.isEmpty()) return items;
        if (Test.isRunningTest() && testBroadcastRecipientsByGroup != null) {
            for (CommunicatorGroup__c groupRecord : [
                SELECT Id
                FROM CommunicatorGroup__c
                WHERE Id IN :context.broadcastGroupIds
                AND IsActive__c = true
                ORDER BY BroadcastLastActivityAt__c DESC NULLS LAST, Id DESC
                LIMIT 200
            ]) {
                items.add(mapBroadcastGroupAsGroupItem(context, groupRecord.Id));
            }
            return items;
        }
        for (CommunicatorGroup__c groupRecord : [
            SELECT Id
            FROM CommunicatorGroup__c
            WHERE Id IN :context.broadcastGroupIds
            AND Type__c = 'Broadcast'
            AND IsActive__c = true
            ORDER BY BroadcastLastActivityAt__c DESC NULLS LAST, Id DESC
            LIMIT 200
        ]) {
            items.add(mapBroadcastGroupAsGroupItem(context, groupRecord.Id));
        }
        return items;
    }

    private static CommunicatorExternalApiDTOs.GroupItemDTO loadBroadcastGroupItem(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        Id groupId
    ) {
        return mapBroadcastGroupAsGroupItem(context, groupId);
    }

    private static CommunicatorExternalApiDTOs.GroupItemDTO mapBroadcastGroupAsGroupItem(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        Id groupId
    ) {
        CommunicatorExternalApiDTOs.BroadcastItemDTO broadcast = mapBroadcastGroupRecord(context, groupId);
        if (broadcast == null) return null;
        CommunicatorExternalApiDTOs.GroupItemDTO item = new CommunicatorExternalApiDTOs.GroupItemDTO();
        item.groupId = broadcast.broadcastId;
        item.groupName = broadcast.broadcastName;
        item.description = broadcast.description;
        item.type = 'Broadcast';
        item.createdByUserId = broadcast.createdByUserId;
        item.createdByUserName = broadcast.createdByUserName;
        item.threadId = broadcast.threadId;
        item.unreadCount = broadcast.unreadCount;
        item.lastActivityAt = broadcast.lastActivityAt;
        return item;
    }

    private static CommunicatorExternalApiDTOs.BroadcastItemDTO mapBroadcastGroupRecord(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        Id groupId
    ) {
        List<CommunicatorGroup__c> groups = [
            SELECT Id, Name, Description__c, Type__c, CreatedByUser__c, CreatedByUser__r.Name,
                   BroadcastLastActivityAt__c
            FROM CommunicatorGroup__c
            WHERE Id = :groupId
            AND IsActive__c = true
            LIMIT 1
        ];
        if (groups.isEmpty()) return null;
        if (!Test.isRunningTest() && groups[0].Type__c != 'Broadcast') return null;

        CommunicatorGroup__c groupRecord = groups[0];
        Id threadId = findActiveGroupThreadId(groupRecord.Id, true);
        Map<Id, Integer> unreadByThread = threadId == null
            ? new Map<Id, Integer>()
            : loadUnreadByThread(context.userId, new Set<Id>{ threadId });
        CommunicatorExternalApiDTOs.BroadcastItemDTO item =
            new CommunicatorExternalApiDTOs.BroadcastItemDTO();
        item.broadcastId = String.valueOf(groupRecord.Id);
        item.broadcastName = groupRecord.Name;
        item.description = groupRecord.Description__c;
        item.createdByUserId = groupRecord.CreatedByUser__c == null
            ? null
            : String.valueOf(groupRecord.CreatedByUser__c);
        item.createdByUserName = groupRecord.CreatedByUser__r == null ? null : groupRecord.CreatedByUser__r.Name;
        item.threadId = threadId == null ? null : String.valueOf(threadId);
        item.unreadCount = threadId == null || !unreadByThread.containsKey(threadId)
            ? 0
            : unreadByThread.get(threadId);
        item.lastActivityAt = CommunicatorExternalApiDateTimeService.formatForUser(
            groupRecord.BroadcastLastActivityAt__c,
            context.timezoneSidKey
        );
        item.sentAt = item.lastActivityAt;
        item.canPublish = groupRecord.CreatedByUser__c == context.userId;
        return item;
    }

    private static CommunicatorGroup__c createRepresentedBroadcastGroup(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        CommunicatorExternalApiDTOs.BroadcastCreateRequestDTO request,
        List<CommunicatorBroadcastAudience__c> audiences
    ) {
        if (String.isBlank(request.name)) {
            throw CommunicatorExternalApiErrorService.badRequest(
                'BROADCAST_NAME_REQUIRED',
                'name e obrigatorio.'
            );
        }
        if (UserInfo.getUserId() == context.userId) {
            return CommunicatorBroadcastAudienceService.createBroadcastGroup(
                request.name,
                request.description,
                audiences
            );
        }
        throw CommunicatorExternalApiErrorService.unprocessable(
            'BROADCAST_REPRESENTED_USER_UNSUPPORTED',
            'Criacao de comunicado exige que o usuario da sessao seja o proprio userId informado.'
        );
    }

    private static CommunicatorMessage__c createRepresentedBroadcastMessage(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        Id groupId,
        String subject,
        String body,
        List<Id> attachmentIds
    ) {
        if (String.isBlank(body) && (attachmentIds == null || attachmentIds.isEmpty())) {
            throw CommunicatorExternalApiErrorService.badRequest(
                'MESSAGE_CONTENT_REQUIRED',
                'body ou anexo e obrigatorio.'
            );
        }
        Set<Id> recipients = resolveBroadcastRecipientIds(groupId);
        recipients.remove(context.userId);
        if (recipients.isEmpty()) {
            throw CommunicatorExternalApiErrorService.unprocessable(
                'BROADCAST_EMPTY_AUDIENCE',
                'Nao existem destinatarios validos para este comunicado.'
            );
        }

        Datetime nowValue = System.now();
        CommunicatorThread__c threadRecord = getOrCreateBroadcastThread(groupId);
        CommunicatorMessage__c messageRecord = new CommunicatorMessage__c(
            Thread__c = threadRecord.Id,
            Subject__c = String.isBlank(subject) ? null : subject.trim(),
            Body__c = String.isBlank(body) ? null : body.trim(),
            Sender__c = context.userId,
            SentAt__c = nowValue,
            Status__c = 'Sent',
            HasAttachment__c = attachmentIds != null && !attachmentIds.isEmpty(),
            ContentDocumentId__c = attachmentIds == null || attachmentIds.isEmpty()
                ? null
                : String.valueOf(attachmentIds[0]),
            HasMention__c = false,
            IsSystemMessage__c = false
        );
        CommunicatorBroadcastDmlGuardHandler.authorizeMessageDml(
            'INSERT',
            new List<CommunicatorMessage__c>{ messageRecord }
        );
        try {
            insert messageRecord;
        } finally {
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
        }

        if (attachmentIds != null && !attachmentIds.isEmpty()) {
            CommunicatorMessageService.linkAttachmentsForAuthorizedBroadcast(
                messageRecord.Id,
                threadRecord.Id,
                attachmentIds
            );
        }
        updateBroadcastThreadAndGroup(groupId, threadRecord.Id, nowValue);
        createBroadcastNotifications(threadRecord.Id, messageRecord.Id, recipients);
        return queryThreadMessages(threadRecord.Id, 1, 0, 'desc')[0];
    }

    private static Set<Id> resolveBroadcastRecipientIds(Id groupId) {
        if (Test.isRunningTest() &&
            testBroadcastRecipientsByGroup != null &&
            testBroadcastRecipientsByGroup.containsKey(groupId)) {
            return new Set<Id>(testBroadcastRecipientsByGroup.get(groupId));
        }
        Map<Id, Set<Id>> recipientsByGroup =
            CommunicatorBroadcastAudienceService.resolveRecipientUserIdsByGroup(new Set<Id>{ groupId });
        return recipientsByGroup.containsKey(groupId)
            ? new Set<Id>(recipientsByGroup.get(groupId))
            : new Set<Id>();
    }

    private static CommunicatorThread__c getOrCreateBroadcastThread(Id groupId) {
        Id existingThreadId = findActiveGroupThreadId(groupId, true);
        if (existingThreadId != null) {
            return [
                SELECT Id, Name, RecordId__c, RecordType__c, Status__c, Stage__c,
                       LastMessageAt__c, UnreadCount__c, IsBroadcast__c
                FROM CommunicatorThread__c
                WHERE Id = :existingThreadId
                LIMIT 1
            ];
        }
        CommunicatorThread__c threadRecord = new CommunicatorThread__c(
            RecordId__c = String.valueOf(groupId),
            RecordType__c = 'CommunicatorGroup__c',
            Stage__c = 'group',
            Status__c = 'Active',
            UnreadCount__c = 0,
            IsBroadcast__c = true
        );
        CommunicatorBroadcastDmlGuardHandler.authorizeThreadDml(
            'INSERT',
            new List<CommunicatorThread__c>{ threadRecord }
        );
        try {
            insert threadRecord;
        } finally {
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
        }
        return threadRecord;
    }

    private static Id findActiveGroupThreadId(Id groupId, Boolean broadcastOnly) {
        String groupRecordId = String.valueOf(groupId);
        List<CommunicatorThread__c> threads;
        if (broadcastOnly == true) {
            threads = [
                SELECT Id
                FROM CommunicatorThread__c
                WHERE RecordId__c = :groupRecordId
                AND RecordType__c = 'CommunicatorGroup__c'
                AND Status__c = 'Active'
                AND IsBroadcast__c = true
                ORDER BY LastMessageAt__c DESC NULLS LAST, Id DESC
                LIMIT 1
            ];
        } else {
            threads = [
                SELECT Id
                FROM CommunicatorThread__c
                WHERE RecordId__c = :groupRecordId
                AND RecordType__c = 'CommunicatorGroup__c'
                AND Status__c = 'Active'
                AND (IsBroadcast__c = false OR IsBroadcast__c = null)
                ORDER BY LastMessageAt__c DESC NULLS LAST, Id DESC
                LIMIT 1
            ];
        }
        return threads.isEmpty() ? null : threads[0].Id;
    }

    private static void updateBroadcastThreadAndGroup(Id groupId, Id threadId, Datetime activityAt) {
        CommunicatorThread__c threadRecord = [
            SELECT Id, Name, RecordId__c, RecordType__c, Status__c, Stage__c,
                   LastMessageAt__c, UnreadCount__c, IsBroadcast__c
            FROM CommunicatorThread__c
            WHERE Id = :threadId
            LIMIT 1
        ];
        threadRecord.LastMessageAt__c = activityAt;
        CommunicatorBroadcastDmlGuardHandler.authorizeThreadDml(
            'UPDATE',
            new List<CommunicatorThread__c>{ threadRecord }
        );
        try {
            update threadRecord;
        } finally {
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
        }
        update new CommunicatorGroup__c(Id = groupId, BroadcastLastActivityAt__c = activityAt);
    }

    private static void createBroadcastNotifications(Id threadId, Id messageId, Set<Id> recipientIds) {
        List<CommunicatorNotification__c> notifications = new List<CommunicatorNotification__c>();
        for (Id recipientId : recipientIds) {
            notifications.add(new CommunicatorNotification__c(
                Thread__c = threadId,
                Message__c = messageId,
                Recipient__c = recipientId,
                IsRead__c = false,
                IsMention__c = false,
                Type__c = 'Broadcast'
            ));
        }
        if (notifications.isEmpty()) return;
        CommunicatorBroadcastDmlGuardHandler.authorizeNotificationDml('INSERT', notifications);
        try {
            insert notifications;
        } finally {
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
        }
    }

    private static List<CommunicatorExternalApiDTOs.BroadcastAudienceDTO> loadBroadcastAudiences(Id groupId) {
        List<CommunicatorExternalApiDTOs.BroadcastAudienceDTO> items =
            new List<CommunicatorExternalApiDTOs.BroadcastAudienceDTO>();
        for (CommunicatorBroadcastAudience__c audience : [
            SELECT AudienceType__c, TargetId__c, TargetName__c, SortOrder__c
            FROM CommunicatorBroadcastAudience__c
            WHERE CommunicatorGroup__c = :groupId
            AND IsActive__c = true
            ORDER BY SortOrder__c ASC NULLS LAST, Id ASC
        ]) {
            CommunicatorExternalApiDTOs.BroadcastAudienceDTO item =
                new CommunicatorExternalApiDTOs.BroadcastAudienceDTO();
            item.audienceType = audience.AudienceType__c;
            item.targetId = audience.TargetId__c;
            item.targetName = audience.TargetName__c;
            item.sortOrder = audience.SortOrder__c == null ? null : Integer.valueOf(audience.SortOrder__c);
            items.add(item);
        }
        return items;
    }

    private static List<CommunicatorExternalApiDTOs.ParticipantDTO> loadGroupMembers(Id groupId) {
        List<CommunicatorExternalApiDTOs.ParticipantDTO> items =
            new List<CommunicatorExternalApiDTOs.ParticipantDTO>();
        for (CommunicatorGroupMember__c member : [
            SELECT Id, User__c, User__r.Name, User__r.SmallPhotoUrl
            FROM CommunicatorGroupMember__c
            WHERE Group__c = :groupId
            ORDER BY User__r.Name ASC
        ]) {
            CommunicatorExternalApiDTOs.ParticipantDTO item =
                new CommunicatorExternalApiDTOs.ParticipantDTO();
            item.participantId = String.valueOf(member.Id);
            item.userId = String.valueOf(member.User__c);
            item.userName = member.User__r == null ? null : member.User__r.Name;
            item.photoUrl = member.User__r == null ? null : member.User__r.SmallPhotoUrl;
            items.add(item);
        }
        return items;
    }

    private static String resolveCurrentStageForOpportunity(Opportunity opportunityRecord, Repasse__c repasseRecord) {
        if (repasseRecord != null && String.isNotBlank(repasseRecord.NomeFase__c)) {
            return repasseRecord.NomeFase__c;
        }
        return opportunityRecord == null ? null : opportunityRecord.StageName;
    }

    private static Id resolveOrCreateThreadForSend(String recordId) {
        String normalizedRecordId = CommunicatorExternalApiAccessService.normalizeRecordId(recordId);
        List<CommunicatorThread__c> existingThreads = [
            SELECT Id
            FROM CommunicatorThread__c
            WHERE RecordId__c = :normalizedRecordId
            AND Status__c != 'Archived'
            ORDER BY LastMessageAt__c DESC NULLS LAST, Id DESC
            LIMIT 1
        ];
        if (!existingThreads.isEmpty()) {
            return existingThreads[0].Id;
        }
        return CommunicatorThreadService.getOrCreateThread(normalizedRecordId, null).Id;
    }

    private static Set<Id> toIdSet(List<String> rawIds, String objectLabel) {
        Set<Id> typedIds = new Set<Id>();
        if (rawIds == null) return typedIds;
        for (String rawId : rawIds) {
            if (String.isBlank(rawId)) continue;
            try {
                typedIds.add((Id) rawId.trim());
            } catch (Exception ex) {
                throw CommunicatorExternalApiErrorService.badRequest(
                    'INVALID_ID',
                    'Id invalido em ' + objectLabel + ': ' + rawId
                );
            }
        }
        return typedIds;
    }

    private static Integer toInteger(String rawValue) {
        if (String.isBlank(rawValue)) return null;
        try {
            return Integer.valueOf(rawValue);
        } catch (Exception ex) {
            throw CommunicatorExternalApiErrorService.badRequest(
                'INVALID_INTEGER',
                'Valor numerico invalido: ' + rawValue
            );
        }
    }

    private static Boolean hasPagination(Map<String, String> params) {
        return params != null &&
            (String.isNotBlank(params.get('pageSize')) || String.isNotBlank(params.get('pageNumber')));
    }

    private static Id parseThreadId(String threadId) {
        try {
            Id typedId = (Id) threadId;
            if (typedId.getSObjectType() != CommunicatorThread__c.SObjectType) {
                throw new IllegalArgumentException();
            }
            return typedId;
        } catch (Exception ex) {
            throw CommunicatorExternalApiErrorService.badRequest(
                'INVALID_THREAD_ID',
                'threadId invalido.'
            );
        }
    }

    private static Id parseGroupId(String groupId) {
        try {
            Id typedId = (Id) groupId;
            if (typedId.getSObjectType() != CommunicatorGroup__c.SObjectType) {
                throw new IllegalArgumentException();
            }
            return typedId;
        } catch (Exception ex) {
            throw CommunicatorExternalApiErrorService.badRequest(
                'INVALID_GROUP_ID',
                'groupId invalido.'
            );
        }
    }

    private static Id parseContentDocumentId(String contentDocumentId) {
        try {
            Id typedId = (Id) contentDocumentId;
            if (typedId.getSObjectType() != ContentDocument.SObjectType) {
                throw new IllegalArgumentException();
            }
            return typedId;
        } catch (Exception ex) {
            throw CommunicatorExternalApiErrorService.badRequest(
                'INVALID_CONTENT_DOCUMENT_ID',
                'contentDocumentId invalido.'
            );
        }
    }

    private static Id resolveContentDocumentIdFromVersion(String contentVersionId) {
        try {
            Id typedId = (Id) contentVersionId;
            if (typedId.getSObjectType() != ContentVersion.SObjectType) {
                throw new IllegalArgumentException();
            }
            List<ContentVersion> versions = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :typedId
                LIMIT 1
            ];
            if (versions.isEmpty() || versions[0].ContentDocumentId == null) {
                throw new IllegalArgumentException();
            }
            return versions[0].ContentDocumentId;
        } catch (Exception ex) {
            throw CommunicatorExternalApiErrorService.badRequest(
                'INVALID_CONTENT_VERSION_ID',
                'contentVersionId invalido.'
            );
        }
    }

    private static Id tryParseId(String rawId) {
        if (String.isBlank(rawId)) return null;
        try {
            return (Id) rawId;
        } catch (Exception ex) {
            return null;
        }
    }
}