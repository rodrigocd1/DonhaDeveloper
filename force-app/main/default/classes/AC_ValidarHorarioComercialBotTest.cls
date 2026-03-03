@isTest
public class AC_ValidarHorarioComercialBotTest 
{
    @isTest
	public static void testeHorarioComercial()
    {
        List<AC_ValidarHorarioComercialBot.Input> Listinput = new List<AC_ValidarHorarioComercialBot.Input>();

        AC_ValidarHorarioComercialBot.Input input = new AC_ValidarHorarioComercialBot.Input();
        input.nomeHorarioComercial = 'Default';
        
        Listinput.add(input);
        
        system.debug('===> ' + AC_ValidarHorarioComercialBot.ValidarHoraComercial(Listinput));
    }
    
    
}