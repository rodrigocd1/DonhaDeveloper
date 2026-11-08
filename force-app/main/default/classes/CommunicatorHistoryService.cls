public with sharing class CommunicatorHistoryService {

    public class HistoryResponse {
        public Boolean success;
        public String error;
        public List<Message> messages;

        public HistoryResponse() {
            success = true;
            messages = new List<Message>();
        }
    }

    public class Message {
        public String id;
        public String body;
        public String authorId;
        public String authorName;
        public Datetime createdAt;
        public String relatedTo;
        public String parentType;
        public String parentName;
    }

    // ENTRY POINT
    public static HistoryResponse getHistory(String id) {
        try {
            validate(id);
            return fetchFeed((Id)id);
        } catch (IllegalArgumentException e) {
            return errorResponse(e.getMessage());
        } catch (Exception e) {
            return errorResponse('Erro inesperado: ' + e.getMessage());
        }
    }

    public static HistoryResponse getHistory(List<String> ids) {
        try {
            validate(ids);

            HistoryResponse response = new HistoryResponse();
            for (String itemId : ids) {
                HistoryResponse partial = fetchFeed((Id)itemId);
                response.messages.addAll(partial.messages);
            }
            return response;
        } catch (IllegalArgumentException e) {
            return errorResponse(e.getMessage());
        } catch (Exception e) {
            return errorResponse('Erro inesperado: ' + e.getMessage());
        }
    }

    // 🔹 Validação
    private static void validate(String id) {
        if (String.isBlank(id)) {
            throw new IllegalArgumentException(
                'Informe ao menos um parâmetro: recordId ou userId.'
            );
        }
    }

    private static void validate(List<String> ids) {
        if (ids == null || ids.isEmpty()) {
            throw new IllegalArgumentException(
                'Informe ao menos um parametro: recordId ou userId.'
            );
        }

        for (String itemId : ids) {
            if (String.isBlank(itemId)) {
                throw new IllegalArgumentException(
                    'Todos os IDs informados devem ser validos.'
                );
            }
        }
    }
    
    private static HistoryResponse fetchFeed(Id id) {

        HistoryResponse response = new HistoryResponse();
        List<FeedItem> feedItems = new List<FeedItem>();
        Map<Id, String> parentTypeMap = new Map<Id, String>();
        Map<Id, String> parentNameMap = new Map<Id, String>();
        Set<Id> parentIds        = new Set<Id>{ id };


        if (String.valueOf(id).startsWith('005')) {

            for (Opportunity opp : [
                SELECT Id, Name, ApuracaoRenda__c, AprovacaoBancaria__c
                FROM Opportunity
                WHERE OwnerId = :id
            ]) {
                parentIds.add(opp.Id);
                parentTypeMap.put(opp.Id, 'Oportunidade');
                parentNameMap.put(opp.Id, opp.Name);
            }

            for (AprovacaoBancaria__c ab : [SELECT Id, Name FROM AprovacaoBancaria__c WHERE OwnerId = :id]) {
                parentIds.add(ab.Id);
                parentTypeMap.put(ab.Id, 'Aprovação Bancaria');
                parentNameMap.put(ab.Id, ab.Name);
            }

            for (AnaliseFinanceira__c af : [SELECT Id, Name FROM AnaliseFinanceira__c WHERE OwnerId = :id]) {
                parentIds.add(af.Id);
                parentTypeMap.put(af.Id, 'Apuração de Renda');
                parentNameMap.put(af.Id, af.Name);
            }

            for (Repasse__c rp : [SELECT Id, Name FROM Repasse__c WHERE OwnerId = :id]) {
                parentIds.add(rp.Id);
                parentTypeMap.put(rp.Id, 'Repasse');
                parentNameMap.put(rp.Id, rp.Name);
            }

            Set<Id> quoteIds = new Set<Id>();

            for (Quote qt : [SELECT Id, Name FROM Quote WHERE OwnerId = :id]) {
                quoteIds.add(qt.Id);
                parentIds.add(qt.Id);
                parentTypeMap.put(qt.Id, 'Cotação');
                parentNameMap.put(qt.Id, qt.Name);
            }

            for (QuoteLineItem  ql : [SELECT Id FROM QuoteLineItem  WHERE QuoteId = :quoteIds]) {
                parentIds.add(ql.Id);
                parentTypeMap.put(ql.Id, 'Quote Line Item');
            }

            for (User u : [SELECT Id, Name FROM User WHERE Id IN :parentIds]) {
                parentIds.add(u.Id);
                parentTypeMap.put(u.Id, 'Usuário');
                parentNameMap.put(u.Id, u.Name);
            }

        } else {

            Set<Id> oppIds = new Set<Id>();
            Set<Id> afIds = new Set<Id>();
            Set<Id> quoteIds = new Set<Id>();

             for (Opportunity opp : [
                SELECT Id, Name, ApuracaoRenda__c, AprovacaoBancaria__c
                FROM Opportunity
                WHERE Id = :id
            ]) {
                oppIds.add(opp.Id);
                parentTypeMap.put(opp.Id, 'Oportunidade');
                parentNameMap.put(opp.Id, opp.Name);
            }

            for (AnaliseFinanceira__c af : [SELECT Id, Name FROM AnaliseFinanceira__c WHERE Oportunidade__c = :oppIds]) {
                afIds.add(af.Id);
                parentIds.add(af.Id);
                parentTypeMap.put(af.Id, 'Apuração de Renda');
                parentNameMap.put(af.Id, af.Name);
            }

            for (AprovacaoBancaria__c ab : [SELECT Id, Name FROM AprovacaoBancaria__c WHERE AnaliseCredito__c = :afIds]) {
                parentIds.add(ab.Id);
                parentTypeMap.put(ab.Id, 'Aprovação Bancaria');
                parentNameMap.put(ab.Id, ab.Name);
            }

            for (Repasse__c rp : [SELECT Id, Name FROM Repasse__c WHERE Oportunidade__c = :oppIds]) {
                parentIds.add(rp.Id);
                parentTypeMap.put(rp.Id, 'Repasse');
                parentNameMap.put(rp.Id, rp.Name);
            }

            for (Quote qt : [SELECT Id, Name FROM Quote WHERE OpportunityId = :oppIds]) {
                quoteIds.add(qt.Id);
                parentIds.add(qt.Id);
                parentTypeMap.put(qt.Id, 'Cotação');
                parentNameMap.put(qt.Id, qt.Name);
            }
            for (QuoteLineItem  ql : [SELECT Id FROM QuoteLineItem  WHERE QuoteId = :quoteIds]) {
                quoteIds.add(ql.Id);
                parentIds.add(ql.Id);
                parentTypeMap.put(ql.Id, 'Quote Line Item');
            }
        }

        feedItems = [
            SELECT Id, Body, CreatedDate, CreatedById, CreatedBy.Name, ParentId
            FROM FeedItem
            WHERE ParentId IN :parentIds
            ORDER BY CreatedDate DESC
        ];

        Set<Id> feedItemIds = new Set<Id>();
        for (FeedItem fi : feedItems) {
            feedItemIds.add(fi.Id);
        }

        Map<Id, List<FeedComment>> commentsMap = new Map<Id, List<FeedComment>>();
        for (FeedComment fc : [
            SELECT Id, CommentBody, CreatedDate, CreatedById, CreatedBy.Name, FeedItemId
            FROM FeedComment
            WHERE FeedItemId IN :feedItemIds
            ORDER BY CreatedDate ASC
        ]) {
            if (!commentsMap.containsKey(fc.FeedItemId)) {
                commentsMap.put(fc.FeedItemId, new List<FeedComment>());
            }
            commentsMap.get(fc.FeedItemId).add(fc);
        }

        // ─── Converter tudo pra Message ──────────────────────────────────────
        for (FeedItem fi : feedItems) {
            response.messages.add(toMessage(fi, parentTypeMap, parentNameMap));

            if (commentsMap.containsKey(fi.Id)) {
                for (FeedComment fc : commentsMap.get(fi.Id)) {
                    response.messages.add(toMessage(fc, parentTypeMap, parentNameMap));
                }
            }
        }

        return response;
    }

    // 🔹 Mapping FeedItem → Message
    private static Message toMessage(FeedItem fi, Map<Id, String> typeMap, Map<Id, String> nameMap) {
        Message m    = new Message();
        m.id         = fi.Id;
        m.body       = fi.Body;
        m.authorId   = fi.CreatedById;
        m.authorName = fi.CreatedBy.Name;
        m.createdAt  = fi.CreatedDate;
        m.relatedTo  = fi.ParentId;
        m.parentType = typeMap.get(fi.ParentId);
        m.parentName = nameMap.get(fi.ParentId);
        return m;
    }

    // 🔹 Mapping FeedComment → Message
    private static Message toMessage(FeedComment fc, Map<Id, String> typeMap, Map<Id, String> nameMap) {
        Message m    = new Message();
        m.id         = fc.Id;
        m.body       = fc.CommentBody;
        m.authorId   = fc.CreatedById;
        m.authorName = fc.CreatedBy.Name;
        m.createdAt  = fc.CreatedDate;
        m.relatedTo  = fc.FeedItemId;
        m.parentType = typeMap.get(fc.FeedItemId);
        m.parentName = nameMap.get(fc.FeedItemId);
        return m;
    }

    private static HistoryResponse errorResponse(String msg) {
        HistoryResponse res = new HistoryResponse();
        res.success = false;
        res.error   = msg;
        return res;
    }
}