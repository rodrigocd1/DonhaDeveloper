// Subclasse concreta Gato que estende a classe Animal
public class Gato extends Animal {
    public Gato(String nome) {
        super(nome);
    }
    
    // Implementação do método fazerSom para Gato
    public override void fazerSom() {
        System.debug(nome + ' faz miados.');
    }
}