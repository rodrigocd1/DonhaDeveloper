/**
 * InteractionChatController
 * Controlador principal do chat por registro.
 * Suposições de objetos custom documentadas no prompt.
 */
public with sharing class InteractionChatController {

    // ─── DTOs ────────────────────────────────────────────────────────────────

    public class ThreadDTO {
        @AuraEnabled public String  id          { get; set; }
        @AuraEnabled public String  recordId    { get; set; }
        @AuraEnabled public String  status      { get; set; }
        @AuraEnabled public String  reason      { get; set; }
        @AuraEnabled public Boolean isClosed    { get; set; }
    }

    public class MessageDTO {
        @AuraEnabled public String   id              { get; set; }
        @AuraEnabled public DateTime createdDate     { get; set; }
        @AuraEnabled public String   senderName      { get; set; }
        @AuraEnabled public String   senderId        { get; set; }
        @AuraEnabled public String   body            { get; set; }
        @AuraEnabled public String   messageType     { get; set; }
        @AuraEnabled public String   fileDocumentId  { get; set; }
    }

    // ─── Access helpers ──────────────────────────────────────────────────────

    @TestVisible
    private static Boolean hasCustomPermission() {
        return FeatureManagement.checkPermission('CanUseInteractionChat');
    }

    @TestVisible
    private static Boolean isParticipant(Id threadId) {
        return [
            SELECT COUNT()
            FROM InteractionParticipant__c
            WHERE Thread__c = :threadId
              AND User__c   = :UserInfo.getUserId()
        ] > 0;
    }

    private static void assertAccess(Id threadId) {
        if (!isParticipant(threadId) && !hasCustomPermission()) {
            throw new AuraHandledException('Acesso negado: usuário não é participante desta thread.');
        }
    }

    private static Boolean isValidRecordId(String rid) {
        if (rid == null) return false;
        return rid.length() == 15 || rid.length() == 18;
    }

    // ─── Methods ─────────────────────────────────────────────────────────────

    /**
     * Retorna thread existente ou null.
     */
    @AuraEnabled(cacheable=false)
    public static ThreadDTO getThreadByRecord(String recordId) {
        if (!isValidRecordId(recordId)) {
            throw new AuraHandledException('recordId inválido.');
        }
        List<InteractionThread__c> threads = [
            SELECT Id, RecordId__c, Status__c, Reason__c, IsClosed__c
            FROM   InteractionThread__c
            WHERE  RecordId__c = :recordId
              AND  IsClosed__c = false
            LIMIT  1
        ];
        if (threads.isEmpty()) return null;
        return toThreadDTO(threads[0]);
    }

    /**
     * Busca ou cria thread. Se não existir, cria thread + participante atual + mensagem inicial.
     */
    @AuraEnabled(cacheable=false)
    public static ThreadDTO getOrCreateThread(
        String recordId,
        String objectApiName,
        String reason,
        String initialMessage
    ) {
        if (!isValidRecordId(recordId)) {
            throw new AuraHandledException('recordId inválido.');
        }

        ThreadDTO existing = getThreadByRecord(recordId);
        if (existing != null) {
            assertAccess(existing.id);
            return existing;
        }

        // Criar thread
        InteractionThread__c thread = new InteractionThread__c(
            RecordId__c      = recordId,
            SObjectApiName__c = objectApiName,
            Status__c        = 'Open',
            Reason__c        = reason,
            IsClosed__c      = false
        );
        insert thread;

        // Adicionar criador como participante
        InteractionParticipant__c part = new InteractionParticipant__c(
            Thread__c = thread.Id,
            User__c   = UserInfo.getUserId(),
            Role__c   = hasCustomPermission() ? 'Internal' : 'Partner'
        );
        insert part;

        // Mensagem inicial
        if (String.isNotBlank(initialMessage)) {
            InteractionMessage__c msg = new InteractionMessage__c(
                Thread__c   = thread.Id,
                Sender__c   = UserInfo.getUserId(),
                Body__c     = initialMessage.abbreviate(32000),
                MessageType__c = 'UserMessage'
            );
            insert msg;
        }

        return toThreadDTO(thread);
    }

    /**
     * Retorna últimas N mensagens da thread.
     */
    @AuraEnabled(cacheable=false)
    public static List<MessageDTO> getMessages(String threadId, Integer limitSize) {
        assertAccess(threadId);
        if (limitSize == null || limitSize <= 0) limitSize = 20;
        limitSize = Math.min(limitSize, 100);

        List<InteractionMessage__c> msgs = [
            SELECT Id, CreatedDate, Sender__r.Name, Sender__c,
                   Body__c, MessageType__c, FileDocumentId__c
            FROM   InteractionMessage__c
            WHERE  Thread__c = :threadId
            ORDER BY CreatedDate ASC
            LIMIT  :limitSize
        ];
        return toMessageDTOList(msgs);
    }

    /**
     * Retorna mensagens criadas após sinceCreatedDate (polling incremental).
     */
    @AuraEnabled(cacheable=false)
    public static List<MessageDTO> getMessagesSince(String threadId, DateTime sinceCreatedDate) {
        assertAccess(threadId);
        List<InteractionMessage__c> msgs = [
            SELECT Id, CreatedDate, Sender__r.Name, Sender__c,
                   Body__c, MessageType__c, FileDocumentId__c
            FROM   InteractionMessage__c
            WHERE  Thread__c    = :threadId
              AND  CreatedDate  > :sinceCreatedDate
            ORDER BY CreatedDate ASC
            LIMIT  50
        ];
        return toMessageDTOList(msgs);
    }

    /**
     * Envia mensagem de texto.
     */
    @AuraEnabled(cacheable=false)
    public static MessageDTO postMessage(String threadId, String body) {
        assertAccess(threadId);
        InteractionThread__c thread = [
            SELECT IsClosed__c FROM InteractionThread__c WHERE Id = :threadId LIMIT 1
        ];
        if (thread.IsClosed__c) {
            throw new AuraHandledException('Thread encerrada. Não é possível enviar mensagens.');
        }
        if (String.isBlank(body)) {
            throw new AuraHandledException('Mensagem não pode ser vazia.');
        }
        InteractionMessage__c msg = new InteractionMessage__c(
            Thread__c      = threadId,
            Sender__c      = UserInfo.getUserId(),
            Body__c        = body.abbreviate(32000),
            MessageType__c = 'UserMessage'
        );
        insert msg;
        return toMessageDTO([
            SELECT Id, CreatedDate, Sender__r.Name, Sender__c,
                   Body__c, MessageType__c, FileDocumentId__c
            FROM   InteractionMessage__c WHERE Id = :msg.Id
        ]);
    }

    /**
     * Altera status da thread e registra evento de mudança.
     */
    @AuraEnabled(cacheable=false)
    public static MessageDTO changeStatus(String threadId, String status) {
        assertAccess(threadId);
        InteractionThread__c thread = [
            SELECT Id, Status__c, IsClosed__c FROM InteractionThread__c WHERE Id = :threadId LIMIT 1
        ];
        thread.Status__c  = status;
        thread.IsClosed__c = (status == 'Closed');
        update thread;

        InteractionMessage__c msg = new InteractionMessage__c(
            Thread__c      = threadId,
            Sender__c      = UserInfo.getUserId(),
            Body__c        = 'Status alterado para: ' + status,
            MessageType__c = 'StatusChange'
        );
        insert msg;
        return toMessageDTO([
            SELECT Id, CreatedDate, Sender__r.Name, Sender__c,
                   Body__c, MessageType__c, FileDocumentId__c
            FROM   InteractionMessage__c WHERE Id = :msg.Id
        ]);
    }

    /**
     * Registra arquivo enviado via lightning-file-upload como evento na timeline.
     * O lightning-file-upload com recordId=threadId já cria o ContentDocumentLink para a thread.
     * TODO: criar ContentDocumentLink adicional ao registro alvo (ex: Opportunity).
     */
    @AuraEnabled(cacheable=false)
    public static MessageDTO linkUploadedFileToThread(String threadId, String contentDocumentId) {
        assertAccess(threadId);

        // Buscar nome do arquivo
        String fileName = '';
        List<ContentDocument> docs = [
            SELECT Title FROM ContentDocument WHERE Id = :contentDocumentId LIMIT 1
        ];
        if (!docs.isEmpty()) fileName = docs[0].Title;

        InteractionMessage__c msg = new InteractionMessage__c(
            Thread__c        = threadId,
            Sender__c        = UserInfo.getUserId(),
            Body__c          = 'Arquivo: ' + fileName,
            MessageType__c   = 'File',
            FileDocumentId__c = contentDocumentId
        );
        insert msg;
        return toMessageDTO([
            SELECT Id, CreatedDate, Sender__r.Name, Sender__c,
                   Body__c, MessageType__c, FileDocumentId__c
            FROM   InteractionMessage__c WHERE Id = :msg.Id
        ]);
    }

    // ─── Converters ──────────────────────────────────────────────────────────

    private static ThreadDTO toThreadDTO(InteractionThread__c t) {
        ThreadDTO dto  = new ThreadDTO();
        dto.id         = t.Id;
        dto.recordId   = t.RecordId__c;
        dto.status     = t.Status__c;
        dto.reason     = t.Reason__c;
        dto.isClosed   = t.IsClosed__c;
        return dto;
    }

    private static MessageDTO toMessageDTO(InteractionMessage__c m) {
        MessageDTO dto    = new MessageDTO();
        dto.id            = m.Id;
        dto.createdDate   = m.CreatedDate;
        dto.senderName    = m.Sender__r != null ? m.Sender__r.Name : '';
        dto.senderId      = m.Sender__c;
        dto.body          = m.Body__c;
        dto.messageType   = m.MessageType__c;
        dto.fileDocumentId = m.FileDocumentId__c;
        return dto;
    }

    private static List<MessageDTO> toMessageDTOList(List<InteractionMessage__c> msgs) {
        List<MessageDTO> result = new List<MessageDTO>();
        for (InteractionMessage__c m : msgs) result.add(toMessageDTO(m));
        return result;
    }
}
