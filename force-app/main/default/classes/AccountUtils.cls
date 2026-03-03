public class AccountUtils 
{
	public static list< Account > accountsByState(String abbreviation)
    {
        List< Account > listaContas = new List< Account >();
        
        Account conta = new Account();
        
        conta.Ship_to__c = abbreviation.abbreviate(80);
        
        listaContas.add( conta );
        
        return listaContas;
    }
}