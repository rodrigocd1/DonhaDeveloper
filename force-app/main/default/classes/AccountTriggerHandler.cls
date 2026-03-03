public class AccountTriggerHandler 
{
	public static void CreateAccounts( List< Account > listAccount , Boolean isBefore , Boolean isInsert)    
    {
        if( isBefore && isInsert )
        {
            for(Account conta: listAccount)
            {
                conta.ShippingState = conta.BillingState;
            }
        }
    }
}