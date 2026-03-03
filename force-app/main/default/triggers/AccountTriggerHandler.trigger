trigger AccountTriggerHandler on Account (before insert ) 
{

    public static void CreateAccounts( List< Account > listAccount)    
    {
                
        for(Account conta: listAccount)
        {
            conta.ShippingState = conta.BillingState;
        }
    }
    
}