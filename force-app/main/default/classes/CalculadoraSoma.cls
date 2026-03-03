public class CalculadoraSoma implements CalculoInterface
{    
    public static Decimal calcularTotal(Decimal valor1, Decimal valor2) 
    {
        Decimal total = valor1 + valor2;
        system.debug('TOTAL ' +  total );
        return total;
    }   
    
    public static Decimal calcularTota(Decimal valor1, Decimal valor2) 
    {
        Decimal total = valor1 + valor2;
        system.debug('TOTAL ' +  total );
        return total;
    }     
    
    
    
}