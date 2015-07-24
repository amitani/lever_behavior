// for Mega
#include <AccelStepper.h>

unsigned int us_in_loop=1000;
unsigned long current_loop_us;

String serialBuffer = "";
String command = "";
char output[128];

unsigned int PIN_BITCODE = 3;
unsigned int PIN_NFB=4;

unsigned int PIN_ORIGIN = 9;
unsigned int PIN_LIMIT = 10;

AccelStepper stepper(4,22,23,24,25);
unsigned int PIN_STEPPER_ENABLE = 30;
bool pin_stepper_enable_status=false;

unsigned int PIN_WATER = 28;

unsigned int PIN_BEEP = 12;

unsigned int PIN_LICK = 52;

unsigned int PIN_LEVER = 0;

enum{
  INIT,
  BITCODE,
  ITI,
  MOVE,
  RESPONSE,
  NFB_DELAY,
  RESET,
  PAUSE
} state=PAUSE, next_state=PAUSE, prev_state=PAUSE, next_trial_state=PAUSE, state_after_init=PAUSE;
unsigned long state_start_us;

unsigned long init_timeout_us=5000000;
unsigned long us_per_bitcode=5000;
unsigned int nbits=12;

struct Params{
  unsigned long iti_us;
  unsigned long response_us;
  unsigned long nfb_delay_us;  
  unsigned long nfb_window;
  
  unsigned long water_hit_us;
  unsigned long water_nfb_on_us;
  unsigned long water_nfb_off_us;
  
  unsigned int open_steps;
}params={4000UL*1000,10000UL*1000,700UL*1000,1000UL*1000,100UL*1000,0,0, 5},new_params=params;
// set 4000 300 10000 500 1000 1000 100 0 0 50

unsigned long water_start_us=0;
unsigned long water_duration_us=0;

struct Hysteretic{
    unsigned long last_on_us, last_off_us;
    bool raw, current;
    unsigned long on_delay_us,off_delay_us;
    Hysteretic(unsigned long on_delay, unsigned long off_delay)
     :on_delay_us(on_delay),off_delay_us(off_delay),
      last_on_us(micros()-10*on_delay),last_off_us(micros()),
      raw(false),current(false){};
    void new_value(bool x){
      raw=x;
      if(x)last_on_us=current_loop_us;else last_off_us=current_loop_us;
      if(current_loop_us-last_off_us>on_delay_us) current=true;
      if(current_loop_us-last_on_us>off_delay_us) current=false;
    }
    void reset(bool x=false){
      current=raw=x;
      last_on_us=current_loop_us-on_delay_us;
      last_off_us=current_loop_us-off_delay_us;
    }
    operator bool(){return current;};
};

unsigned long loop_count;
Hysteretic hit(2000,50000),origin(2000,50000),nfb(0,params.nfb_window),lick(2000,2000);
bool water,bitcode;
unsigned int lever_position;

unsigned int trial_count;
bool hit_reward;  

bool to_reset=true;

unsigned int limit_position=0; //0:at the origin, 1: max
unsigned int current_position=0;

unsigned int const OUTPUT_BUFFER_SIZE=32;
byte const OUTPUT_BYTE_END = -1;
byte const OUTPUT_BYTE_ESCAPE = -2;
struct Output_buffer{
  byte output_buffer[OUTPUT_BUFFER_SIZE];
  unsigned int current_length;
  void init(){
    current_length=0;
    memset(output_buffer,OUTPUT_BYTE_END,OUTPUT_BUFFER_SIZE);
  }
  void add_data(byte b){
    if(current_length>=OUTPUT_BUFFER_SIZE) return;
    if(b==OUTPUT_BYTE_ESCAPE || b==OUTPUT_BYTE_END){
      output_buffer[current_length]=OUTPUT_BYTE_ESCAPE;
      current_length++;
      if(current_length>=OUTPUT_BUFFER_SIZE) return;
      output_buffer[current_length]=-b;
      current_length++;
    }else{
      output_buffer[current_length]=b;
      current_length++;
    }
  }
}output_buffer;

#define SerialControl Serial
#define SerialData Serial2

void setup() {
  pinMode(LED_BUILTIN,OUTPUT);digitalWrite(LED_BUILTIN,LOW);
  pinMode(PIN_BITCODE,OUTPUT);digitalWrite(PIN_BITCODE,LOW);
  pinMode(PIN_WATER,OUTPUT);digitalWrite(PIN_WATER,LOW);
  pinMode(PIN_STEPPER_ENABLE,OUTPUT);digitalWrite(PIN_STEPPER_ENABLE,LOW);
  pinMode(PIN_NFB,INPUT_PULLUP);
  pinMode(PIN_LIMIT,INPUT_PULLUP);
  pinMode(PIN_ORIGIN,INPUT_PULLUP);
  pinMode(PIN_LICK,INPUT_PULLUP);
  
  stepper.setAcceleration(5000.0);
  
  SerialControl.begin(115200);
  SerialData.begin(230400);
  
  serialBuffer.reserve(256);
  command.reserve(128);
  
  current_loop_us = micros();
}
void loop() {
  stepper.run();
  
  // handle Serial commands
  while (SerialControl.available()){
    char c=(char)SerialControl.read();
    serialBuffer += c;
    // SerialControl.print(c);
  }
  while(serialBuffer.indexOf('\n')>=0){
    command=serialBuffer.substring(0,serialBuffer.indexOf('\n'));
    serialBuffer.remove(0,1+serialBuffer.indexOf('\n'));
    SerialControl.print("> "+command+'\n');
    if(command.startsWith("pause"))next_trial_state=PAUSE;
    else if(command.startsWith("resume"))next_trial_state=BITCODE;
    else if(command.startsWith("start")){to_reset=true;next_trial_state=BITCODE;}
    else if(command.startsWith("water ")){
      command=command.substring(command.indexOf(' ')+1);
      if(command=="on") water_duration_us=-1;
      else if(command=="off") water_duration_us=0;
      else{
        water_start_us=current_loop_us;
        water_duration_us=command.toInt()*1000;
      }
      command="";
    }else if(command.startsWith("set ")){
      command.remove(0,1+command.indexOf(' '));
      command=command+' ';
      for(int i=0;i<7;i++){
        if(command.indexOf(' ')<0) break;
        *(i+(unsigned long*)&new_params)=long(command.substring(0,command.indexOf(' ')).toInt())*1000L;
        //SerialControl.print(*(i+(unsigned long*)&new_params)); SerialControl.print("\n");
        if(command.indexOf(' ')>=0)command.remove(0,1+command.indexOf(' '));
      }
      if(command.indexOf(' ')<0) break;
      *(unsigned int*)(7+(unsigned long*)&new_params)=command.substring(0,command.indexOf(' ')).toInt();
    }else if(command.startsWith("lever ")){
      command=command.substring(command.indexOf(' ')+1);
      if(command=="reinit"){
        state_after_init=next_trial_state;
        next_trial_state=INIT;
      }else if(command=="off"){
        digitalWrite(PIN_STEPPER_ENABLE,LOW);pin_stepper_enable_status=false;
      }else SerialControl.print("! Lever command argument parse error.\n");
    }else{
      SerialControl.print("! Command parse error.\n");
    }
  }
  
  // time loop
  if(micros()-current_loop_us<us_in_loop) return;
  current_loop_us+=us_in_loop;
  loop_count++;
  while(micros()-current_loop_us>us_in_loop){
    SerialControl.print("S:");
    SerialControl.print(loop_count&65535);
    SerialControl.print("\n");
    current_loop_us+=us_in_loop;
    loop_count++;
  }

  // input
  hit.new_value(!digitalRead(PIN_LIMIT));
  origin.new_value(!digitalRead(PIN_ORIGIN));
  nfb.new_value(digitalRead(PIN_NFB));
  lick.new_value(digitalRead(PIN_LICK));
  lever_position=analogRead(PIN_LEVER);
  
  if(loop_count%100==-1){
     SerialControl.print(hit.raw);
     SerialControl.print("\t");
     SerialControl.print(hit.current);
     SerialControl.print("\t");
     SerialControl.print(origin.raw);
     SerialControl.print("\t");
     SerialControl.print(origin.current);
     SerialControl.print("\t");
     SerialControl.print(stepper.currentPosition());
     SerialControl.print("\t");
     SerialControl.print(stepper.distanceToGo());
     SerialControl.print("\n");
  }
  
  // state transitions
  prev_state=state;
  if(next_state!=state){
    state=next_state;
    state_start_us=current_loop_us;
  }
  if(state!=prev_state){
    SerialControl.print("State ");
    SerialControl.print(state);
    SerialControl.print("\n");
  }
  
  if(state==INIT){
    if(state!=prev_state){
      SerialControl.print("Initializing.\n");
      digitalWrite(PIN_STEPPER_ENABLE,HIGH);pin_stepper_enable_status=true;
      stepper.setMaxSpeed(20.0);
      stepper.move(100);
    }
    if(hit&&origin||current_loop_us-state_start_us>init_timeout_us){
      stepper.setCurrentPosition(0);
      stepper.moveTo(0);
      SerialControl.print("Done.\n");
      stepper.setMaxSpeed(200.0);
      next_state=next_trial_state=state_after_init;
    }
  }else if(state==BITCODE){
    if(state!=prev_state){
      if(!pin_stepper_enable_status){
        next_state=INIT;
        next_trial_state=state_after_init=BITCODE;
        return;
      }
      hit_reward=false;      
      if(to_reset){
        trial_count=1;
        to_reset = false;
      }else{
        trial_count++;
      }
      if(memcmp(&params, &new_params, sizeof(params))!=0){
        params=new_params;
        nfb.off_delay_us=params.nfb_window;
        SerialControl.print("Updated parameters.\n");
      }
    }
    int nth_bit=(current_loop_us-state_start_us)/us_per_bitcode;
    if(nth_bit==0) bitcode=true;
    else if(nth_bit<=nbits) bitcode=trial_count&1<<(nbits-nth_bit);
    else {bitcode=false;next_state=ITI;}
  }else if(state==ITI){
    if(current_loop_us-state_start_us>params.iti_us){next_state=MOVE;}
  }else if(state==MOVE){
    if(state!=prev_state){
      stepper.setMaxSpeed(200.0);
      stepper.moveTo(-1*(long)params.open_steps);
    }
    if(stepper.distanceToGo()==0){next_state=RESPONSE;hit.reset();}
  }else if(state==RESPONSE){
    noTone(PIN_BEEP);tone(PIN_BEEP,6000);
    if(hit){
      water_start_us=current_loop_us;
      water_duration_us=params.water_hit_us;
      noTone(PIN_BEEP);tone(PIN_BEEP,4000,500);
      hit_reward=true;
      next_state=NFB_DELAY;
    }
    if(current_loop_us-state_start_us>params.response_us){noTone(PIN_BEEP);next_state=RESET;}
  }else if(state==NFB_DELAY){
    if(current_loop_us-state_start_us>params.nfb_delay_us){
      if(params.water_nfb_on_us>0 && nfb){
        water_start_us=current_loop_us;
        water_duration_us=params.water_nfb_on_us;
        noTone(PIN_BEEP);tone(PIN_BEEP,4000,500);
      }
      if(params.water_nfb_off_us>0 && !nfb){
        water_start_us=current_loop_us;
        water_duration_us=params.water_nfb_off_us;
        tone(PIN_BEEP,4000,500);
      }
      next_state=RESET;
    }
  }else if(state==RESET){
    if(state!=prev_state){
      stepper.setMaxSpeed(15.0);
      stepper.moveTo(0);  
    }
    if(stepper.distanceToGo()==0){
      next_state=next_trial_state;
      sprintf(output,"*%4d %s\n",trial_count,hit_reward?"h":"m");
      SerialControl.print(output);
    }
  }else if(state==PAUSE){
    next_state=next_trial_state;
  }
  
  // water
  water=current_loop_us-water_start_us<water_duration_us;
  
  //output
  digitalWrite(PIN_WATER,water?HIGH:LOW);
  digitalWrite(LED_BUILTIN,water?HIGH:LOW);
  digitalWrite(PIN_BITCODE,bitcode?HIGH:LOW);
  
  // serial output
  output_buffer.init();
  output_buffer.add_data(loop_count);
  output_buffer.add_data(loop_count>>8);
  output_buffer.add_data(loop_count>>16);
  output_buffer.add_data(trial_count);
  output_buffer.add_data(trial_count>>8);
  output_buffer.add_data(state);
  output_buffer.add_data(hit.raw<<7|hit.current<<6|origin.raw<<5|origin.current<<4|nfb.raw<<3|nfb.current<<2|water<<1|bitcode);
  output_buffer.add_data(lick.raw<<7|lick.current<<6);
  output_buffer.add_data(stepper.currentPosition());
  output_buffer.add_data(lever_position);
  output_buffer.add_data(lever_position>>8);
  SerialData.write(output_buffer.output_buffer,output_buffer.current_length+1);
}


