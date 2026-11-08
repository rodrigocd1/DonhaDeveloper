public without sharing class CommunicatorBroadcastDistCoordinator implements Queueable {

    private final Id messageId;
    private final Integer criterionIndex;

    public CommunicatorBroadcastDistCoordinator(Id messageId, Integer criterionIndex) {
        this.messageId = messageId;
        this.criterionIndex = criterionIndex == null ? 0 : criterionIndex;
    }

    public void execute(QueueableContext context) {
        CommunicatorBroadcastDistributionService.executeDistributionCoordinator(
            messageId,
            criterionIndex,
            context == null ? null : context.getJobId()
        );
    }
}