trigger AccountTrigger on Account (before insert,before update) 
{
   // Boolean isBefore = Trigger.isBefore;
   // Boolean isInsert = Trigger.isInsert;
   // AccountTriggerHandler.CreateAccounts(Trigger.new, isBefore , isInsert  );
   
   for(Account conta: Trigger.new)
   {
       //conta.AddError(' Erro de Conta ');
   }
}