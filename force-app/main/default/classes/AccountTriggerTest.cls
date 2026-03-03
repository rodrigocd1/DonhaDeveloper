@isTest
public class AccountTriggerTest 
{
	static testmethod void criarContas()
    {
        List< Account > listaConta = new List< Account >();
        
        integer i=0;
        
        for(i=0 ; i<= 200 ; i++)
        {
            Account conta = new Account();
            conta.Name = 'conta ' + i;
           	conta.BillingState = 'CA';
            listaConta.add(conta);
        }
        
        insert listaConta;
        
    }
}