#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/kthread.h>
#include <linux/mm.h>
#include <linux/vmalloc.h>
#include <linux/slab.h>
#include <linux/highmem.h>
#include <asm/page.h>
#include <asm/pgtable.h>

#include "reconos.h"
#include "mbox.h"


#define C_HWT_SLOT_NR 0
#define B_HWT_SLOT_NR 1
#define A_HWT_SLOT_NR 2
#define E_HWT_SLOT_NR 3


struct reconos_resource e_res[2];
struct reconos_hwt e_hwt;
struct reconos_resource a_res[2];
struct reconos_hwt a_hwt;
struct reconos_resource s_res[2];
struct reconos_hwt s_hwt;

struct reconos_resource b_res[2];
struct reconos_hwt b_hwt;
struct reconos_resource c_res[2];
struct reconos_hwt c_hwt;

struct mbox e_mb_put;
struct mbox e_mb_get;
struct mbox a_mb_put;
struct mbox a_mb_get;
struct mbox s_mb_put;
struct mbox s_mb_get;

struct mbox b_mb_put;
struct mbox b_mb_get;
struct mbox c_mb_put;
struct mbox c_mb_get;

//static uint32_t init_data = 0xDEADBEEF;

struct config_data {
	u32 dst_idp:8,
	    src_idp:8,
	    res:6,
	    latency_critical:1,
	    direction:1,
	    priority:2,
	    global_addr:4,
	    local_addr:2;
};

struct noc_pkt {
	u8 hw_addr_switch:4,
	   hw_addr_block:2,
	   priority:2;
	u8 direction:1,
	   latency_critical:1,
	   reserved:6;
	u16 payload_len;
	u32 src_idp;
	u32 dst_idp;
	u8* payload;
};

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
void copy_packet(int len, int start_val, char * addr, int global, int local){
	//hwaddrglobal hwaddrlocal, priority
	struct noc_pkt pkt;
	int i = 0;	
	pkt.hw_addr_switch = global; //(1/0 -> Ethernet, 1/1 -> loop back to SW);
	pkt.hw_addr_block = local;
	pkt.priority = 1;
	pkt.direction = 0;
	pkt.latency_critical = 1;
	pkt.reserved = 0;
	pkt.payload_len = len;
	pkt.src_idp = 0xaabbccaa;
	pkt.dst_idp = 0xddeeffdd;
	memcpy(addr, &pkt, sizeof(struct noc_pkt));
	while (len - i > 0){
		addr[12 + i ]= 17*((i)%256);
		i++;
	}
}
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
void print_packet(struct noc_pkt * pkt){
	printk(KERN_INFO "global addr: %d\n", pkt->hw_addr_switch);
	printk(KERN_INFO "local addr: %d\n", pkt->hw_addr_block);
	printk(KERN_INFO "priority: %d\n", pkt->priority);
	printk(KERN_INFO "direction: %d\n", pkt->direction);
	printk(KERN_INFO "latency critical: %d\n", pkt->latency_critical);
	printk(KERN_INFO "payload_len: %d\n", pkt->payload_len);
	printk(KERN_INFO "src idp: %d\n", pkt->src_idp);
	printk(KERN_INFO "dst idp: %d\n", pkt->dst_idp);
}


static int __init init_reconos_test_module(void)
{
	char * shared_mem_h2s;
	char * shared_mem_s2h;
	int i;
	long unsigned jiffies_before;
	long unsigned jiffies_after;

	printk(KERN_INFO "[reconos-interface] Init.\n");

	mbox_init(&e_mb_put, 2);
    	mbox_init(&e_mb_get, 2);
	mbox_init(&a_mb_put, 2);
    	mbox_init(&a_mb_get, 2);
	mbox_init(&b_mb_put, 2);
    	mbox_init(&b_mb_get, 2);
	mbox_init(&c_mb_put, 2);
    	mbox_init(&c_mb_get, 2);
	printk(KERN_INFO "[reconos-interface] mbox_init done, starting autodetect.\n");

	reconos_init_autodetect();

	printk(KERN_INFO "[reconos-interface] Creating hw-thread.\n");
	e_res[0].type = RECONOS_TYPE_MBOX;
	e_res[0].ptr  = &e_mb_put;	  	
    	e_res[1].type = RECONOS_TYPE_MBOX;
	e_res[1].ptr  = &e_mb_get;

	a_res[0].type = RECONOS_TYPE_MBOX;
	a_res[0].ptr  = &a_mb_put;	  	
    	a_res[1].type = RECONOS_TYPE_MBOX;
	a_res[1].ptr  = &a_mb_get;

	s_res[0].type = RECONOS_TYPE_MBOX;
	s_res[0].ptr  = &s_mb_put;	  	
    	s_res[1].type = RECONOS_TYPE_MBOX;
	s_res[1].ptr  = &s_mb_get;

	b_res[0].type = RECONOS_TYPE_MBOX;
	b_res[0].ptr  = &b_mb_put;	  	
    	b_res[1].type = RECONOS_TYPE_MBOX;
	b_res[1].ptr  = &b_mb_get;

	c_res[0].type = RECONOS_TYPE_MBOX;
	c_res[0].ptr  = &c_mb_put;	  	
    	c_res[1].type = RECONOS_TYPE_MBOX;
	c_res[1].ptr  = &c_mb_get;


	reconos_hwt_setresources(&e_hwt,e_res,2);
	reconos_hwt_create(&e_hwt,E_HWT_SLOT_NR,NULL);

    	reconos_hwt_setresources(&a_hwt,a_res,2);
	reconos_hwt_create(&a_hwt,A_HWT_SLOT_NR,NULL);

	reconos_hwt_setresources(&b_hwt,b_res,2);
	reconos_hwt_create(&b_hwt,B_HWT_SLOT_NR,NULL);

	reconos_hwt_setresources(&c_hwt,c_res,2);
	reconos_hwt_create(&c_hwt,C_HWT_SLOT_NR,NULL);

	//setup the hw -> sw thread
	printk(KERN_INFO "[reconos-interface] Allocate memory\n");
	shared_mem_h2s = get_zeroed_page(GFP_KERNEL);
	printk(KERN_INFO "[reconos-interface] h2s memory %p\n", shared_mem_h2s);
	mbox_put(&b_mb_put, shared_mem_h2s);

	//setup the sw -> hw thread
	shared_mem_s2h = get_zeroed_page(GFP_KERNEL);
	printk(KERN_INFO "[reconos-interface] s2h memory %p\n", shared_mem_s2h);
	mbox_put(&c_mb_put, shared_mem_s2h);
	printk(KERN_INFO "[reconos-interface] HZ= %d\n", HZ);
	jiffies_before = jiffies;

//	for(i = 0; i < 10000; i++)
{
		int packet_len  = 1000;
		int j = 0;
		int result = 0;
		memset(shared_mem_s2h, 0, 2 * packet_len);

		struct noc_pkt * snd_pkt=(struct noc_pkt *)shared_mem_s2h;
		struct noc_pkt * rcv_pkt=(struct noc_pkt *)shared_mem_h2s;

		u32 config_data_start=1;
		u32 config_rcv=0;
		u32 config_data_mode_aes=22;
		u32 config_data_mode_aesde=18;
						//16: 128->eth,		 
						//17: 192->eth, 
						//18/19: 256->eth; 

						//20: 128->h2s(pktsink/aesde), 
						//21: 192->h2s(pktsink/aesde), 
						//22/23: 256->h2s(pktsink/aesde)

		u32 config_data_key0=50462976;	//X"03020100"
		u32 config_data_key1=117835012;	//X"07060504"
		u32 config_data_key2=185207048;	//X"0b0a0908"
		u32 config_data_key3=252579084;	//X"0f0e0d0c"

		u32 config_data_key4=319951120;	//X"13121110"
		u32 config_data_key5=387323156;	//X"17161514"
		u32 config_data_key6=454695192;	//X"1b1a1918"
		u32 config_data_key7=522067228;	//X"1f1e1d1c"
		u32 config_exit_sig=4294967295;	//state_thread_exit

		u32 config_pkt_len=1000;	
		u32 config_pkt_route=5;				//1:0000&&01:aes, 4:0001&00:eth, 5:0001&01:aesde
		//u32 config_pkt_number_tx=2000;
		//u32 config_pkt_number_rx=1000;

//configure e_mbox <hwt_aes>:
		mbox_put(&e_mb_put, config_data_start);
		mbox_put(&e_mb_put, config_data_mode_aesde);
		mbox_put(&e_mb_put, config_data_key0);
		mbox_put(&e_mb_put, config_data_key1);
		mbox_put(&e_mb_put, config_data_key2);
		mbox_put(&e_mb_put, config_data_key3);

		mbox_put(&e_mb_put, config_data_key4);
		mbox_put(&e_mb_put, config_data_key5);
		mbox_put(&e_mb_put, config_data_key6);
		mbox_put(&e_mb_put, config_data_key7);
		config_rcv=mbox_get(&e_mb_get);
		printk(KERN_INFO "hwt_aes configured. \n");
//configure b_mbox <hwt_aesde>
		mbox_put(&b_mb_put, config_data_start);
		mbox_put(&b_mb_put, config_data_mode_aesde);
		mbox_put(&b_mb_put, config_data_key0);
		mbox_put(&b_mb_put, config_data_key1);
		mbox_put(&b_mb_put, config_data_key2);
		mbox_put(&b_mb_put, config_data_key3);

		mbox_put(&b_mb_put, config_data_key4);
		mbox_put(&b_mb_put, config_data_key5);
		mbox_put(&b_mb_put, config_data_key6);
		mbox_put(&b_mb_put, config_data_key7);
		config_rcv=mbox_get(&b_mb_get);
		printk(KERN_INFO "hwt_aesde configured. \n");
//configure c_mbox <hwt_s2h>

                copy_packet(packet_len, 1, shared_mem_s2h, 1, 0);
                mbox_put(&c_mb_put, packet_len);
                result = mbox_get(&c_mb_get);
         	printk(KERN_INFO "[reconos-interface] packet sent received ack from hw, total packet len %d \n", result);
	
		/************************************
		 * send packet to hardware
		 ************************************/
                //copy_packet(packet_len, 2, shared_mem_s2h, 1, 1);
                //mbox_put(&c_mb_put, packet_len);
                //result = mbox_get(&c_mb_get);
         	//printk(KERN_INFO "[reconos-interface] packet sent received ack from hw, total packet len %d \n", result);
//send to aes
                copy_packet(packet_len, 0, shared_mem_s2h, 0, 1); //0000 01=aes
                mbox_put(&c_mb_put, packet_len);
	        result = mbox_get(&c_mb_get);
         	printk(KERN_INFO "encrypted 1:  A[reconos-interface] packet sent received ack from hw, total packet len = %d  \n", result);
//configure e_mbox <hwt_aes>:
		mbox_put(&e_mb_put, config_data_start);
		mbox_put(&e_mb_put, config_data_mode_aes);
		mbox_put(&e_mb_put, config_data_key0);
		mbox_put(&e_mb_put, config_data_key1);
		mbox_put(&e_mb_put, config_data_key2);
		mbox_put(&e_mb_put, config_data_key3);

		mbox_put(&e_mb_put, config_data_key4);
		mbox_put(&e_mb_put, config_data_key5);
		mbox_put(&e_mb_put, config_data_key6);
		mbox_put(&e_mb_put, config_data_key7);
		config_rcv=mbox_get(&e_mb_get);
		printk(KERN_INFO "hwt_aes configured. \n");
//send to aes
                copy_packet(packet_len, 0, shared_mem_s2h, 0, 1); //0000 01=aes
                mbox_put(&c_mb_put, packet_len);
	        result = mbox_get(&c_mb_get);
         	printk(KERN_INFO "encrypted 2:  A[reconos-interface] packet sent received ack from hw, total packet len = %d  \n", result);
//send to aes
                copy_packet(packet_len, 0, shared_mem_s2h, 0, 1); //0000 01=aes
                mbox_put(&c_mb_put, packet_len);
	        result = mbox_get(&c_mb_get);
         	printk(KERN_INFO "encrypted 3:  A[reconos-interface] packet sent received ack from hw, total packet len = %d  \n", result);
//send to aes
                copy_packet(packet_len, 0, shared_mem_s2h, 0, 1); //0000 01=aes
                mbox_put(&c_mb_put, packet_len);
	        result = mbox_get(&c_mb_get);
         	printk(KERN_INFO "encrypted 4:  A[reconos-interface] packet sent received ack from hw, total packet len = %d  \n", result);

		config_data_mode_aes=21;
		config_data_mode_aesde=17;

//configure e_mbox <hwt_aes>:
		mbox_put(&e_mb_put, config_data_start);
		mbox_put(&e_mb_put, config_data_mode_aesde);
		mbox_put(&e_mb_put, config_data_key0);
		mbox_put(&e_mb_put, config_data_key1);
		mbox_put(&e_mb_put, config_data_key2);
		mbox_put(&e_mb_put, config_data_key3);

		mbox_put(&e_mb_put, config_data_key4);
		mbox_put(&e_mb_put, config_data_key5);
		mbox_put(&e_mb_put, config_data_key6);
		mbox_put(&e_mb_put, config_data_key7);
		config_rcv=mbox_get(&e_mb_get);
		printk(KERN_INFO "hwt_aes configured. \n");
//configure b_mbox <hwt_aesde>
		mbox_put(&b_mb_put, config_data_start);
		mbox_put(&b_mb_put, config_data_mode_aesde);
		mbox_put(&b_mb_put, config_data_key0);
		mbox_put(&b_mb_put, config_data_key1);
		mbox_put(&b_mb_put, config_data_key2);
		mbox_put(&b_mb_put, config_data_key3);

		mbox_put(&b_mb_put, config_data_key4);
		mbox_put(&b_mb_put, config_data_key5);
		mbox_put(&b_mb_put, config_data_key6);
		mbox_put(&b_mb_put, config_data_key7);
		config_rcv=mbox_get(&b_mb_get);
		printk(KERN_INFO "hwt_aesde configured. \n");
//send to aes
                copy_packet(packet_len, 0, shared_mem_s2h, 0, 1); //0000 01=aes
                mbox_put(&c_mb_put, packet_len);
	        result = mbox_get(&c_mb_get);
         	printk(KERN_INFO "encrypted 5:  A[reconos-interface] packet sent received ack from hw, total packet len = %d  \n", result);
//configure e_mbox <hwt_aes>:
		mbox_put(&e_mb_put, config_data_start);
		mbox_put(&e_mb_put, config_data_mode_aes);
		mbox_put(&e_mb_put, config_data_key0);
		mbox_put(&e_mb_put, config_data_key1);
		mbox_put(&e_mb_put, config_data_key2);
		mbox_put(&e_mb_put, config_data_key3);

		mbox_put(&e_mb_put, config_data_key4);
		mbox_put(&e_mb_put, config_data_key5);
		mbox_put(&e_mb_put, config_data_key6);
		mbox_put(&e_mb_put, config_data_key7);
		config_rcv=mbox_get(&e_mb_get);
		printk(KERN_INFO "hwt_aes configured. \n");

//send to aes
                copy_packet(packet_len, 0, shared_mem_s2h, 0, 1); //0000 01=aes
                mbox_put(&c_mb_put, packet_len);
	        result = mbox_get(&c_mb_get);
         	printk(KERN_INFO "Final <192> encrypted 1:  A[reconos-interface] packet sent received ack from hw, total packet len = %d  \n", result);
		
	}
	jiffies_after =jiffies;
	printk(KERN_INFO "[reconos-interface] jiffies before = %lu, jiffies after = %lu, delta = %lu", jiffies_before, jiffies_after, jiffies_after - jiffies_before);

	printk(KERN_INFO "[reconos-interface] done\n");
	return 0;
}

static void __exit cleanup_reconos_test_module(void)
{
	reconos_cleanup();

	printk("[reconos-interface] unloaded\n");
}

module_init(init_reconos_test_module);
module_exit(cleanup_reconos_test_module);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Ariane Keller <ariane.keller@tik.ee.ethz.ch>");
MODULE_DESCRIPTION("EmbedNet HW/SW interface");

